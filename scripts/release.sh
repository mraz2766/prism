#!/bin/zsh

set -euo pipefail

release_kind="${1:-small}"
case "$release_kind" in
  small|major) ;;
  *)
    echo "用法：$0 [small|major]" >&2
    exit 64
    ;;
esac

script_dir="${0:A:h}"
project_root="${script_dir:h}"
project_file="$project_root/Prism.xcodeproj/project.pbxproj"
application_path="/Applications/Prism.app"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/prism-release.XXXXXX")"
project_backup="$temporary_root/project.pbxproj"
derived_data="$temporary_root/DerivedData"
install_stage=""
previous_app=""
version_changed=no
install_changed=no

cleanup() {
  local exit_code=$?

  if [[ "$exit_code" -ne 0 && "$install_changed" == yes ]]; then
    if [[ -e "$application_path" ]]; then
      rm -rf -- "$application_path"
    fi
    if [[ -n "$previous_app" && -e "$previous_app" ]]; then
      mv -- "$previous_app" "$application_path"
    fi
  fi

  if [[ "$exit_code" -ne 0 && "$version_changed" == yes && -f "$project_backup" ]]; then
    cp -- "$project_backup" "$project_file"
  fi

  if [[ -n "$install_stage" && -d "$install_stage" ]]; then
    rm -rf -- "$install_stage"
  fi
  if [[ -d "$temporary_root" ]]; then
    rm -rf -- "$temporary_root"
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    echo "发布失败：工程版本与已安装 App 已恢复。" >&2
  fi
}
trap cleanup EXIT

cd "$project_root"
cp -- "$project_file" "$project_backup"

current_version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' "$project_file" | sort -u)"
current_build="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "$project_file" | sort -u)"

if [[ "$(print -r -- "$current_version" | wc -l | tr -d ' ')" != 1 || ! "$current_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "无法解析唯一的 MARKETING_VERSION：$current_version" >&2
  exit 65
fi
if [[ "$(print -r -- "$current_build" | wc -l | tr -d ' ')" != 1 || ! "$current_build" =~ '^[0-9]+$' ]]; then
  echo "无法解析唯一的 CURRENT_PROJECT_VERSION：$current_build" >&2
  exit 65
fi

parts=("${(@s/./)current_version}")
major="${parts[1]}"
minor="${parts[2]}"
patch="${parts[3]:-0}"
if [[ "$release_kind" == small ]]; then
  if (( patch < 9 )); then
    next_version="$major.$minor.$((patch + 1))"
  else
    next_version="$major.$((minor + 1)).0"
  fi
else
  next_version="$((major + 1)).0.0"
fi
next_build="$((current_build + 1))"

CURRENT_VERSION="$current_version" NEXT_VERSION="$next_version" \
  /usr/bin/perl -0pi -e 's/MARKETING_VERSION = \Q$ENV{CURRENT_VERSION}\E;/MARKETING_VERSION = $ENV{NEXT_VERSION};/g' "$project_file"
CURRENT_BUILD="$current_build" NEXT_BUILD="$next_build" \
  /usr/bin/perl -0pi -e 's/CURRENT_PROJECT_VERSION = \Q$ENV{CURRENT_BUILD}\E;/CURRENT_PROJECT_VERSION = $ENV{NEXT_BUILD};/g' "$project_file"
version_changed=yes

echo "Prism $current_version ($current_build) → $next_version ($next_build)"
echo "运行单元测试…"
xcodebuild \
  -project Prism.xcodeproj \
  -scheme Prism \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test

echo "构建签名 Release App…"
xcodebuild \
  -project Prism.xcodeproj \
  -scheme Prism \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  clean build

built_app="$derived_data/Build/Products/Release/Prism.app"
if [[ ! -d "$built_app" ]]; then
  echo "未找到 Release 构建产物：$built_app" >&2
  exit 66
fi

built_version="$(defaults read "$built_app/Contents/Info" CFBundleShortVersionString)"
built_number="$(defaults read "$built_app/Contents/Info" CFBundleVersion)"
if [[ "$built_version" != "$next_version" || "$built_number" != "$next_build" ]]; then
  echo "构建版本不一致：$built_version ($built_number)" >&2
  exit 67
fi
codesign --verify --deep --strict "$built_app"

if [[ ! -w /Applications ]]; then
  echo "当前账户没有 /Applications 写入权限。" >&2
  exit 77
fi

install_stage="$(mktemp -d "/Applications/.prism-install.XXXXXX")"
staged_app="$install_stage/Prism.app"
previous_app="$install_stage/Prism.previous.app"
/usr/bin/ditto "$built_app" "$staged_app"

if pgrep -x Prism >/dev/null 2>&1; then
  pkill -x Prism
fi
install_changed=yes
if [[ -e "$application_path" ]]; then
  mv -- "$application_path" "$previous_app"
fi
mv -- "$staged_app" "$application_path"

installed_version="$(defaults read "$application_path/Contents/Info" CFBundleShortVersionString)"
installed_build="$(defaults read "$application_path/Contents/Info" CFBundleVersion)"
if [[ "$installed_version" != "$next_version" || "$installed_build" != "$next_build" ]]; then
  echo "安装版本验证失败：$installed_version ($installed_build)" >&2
  exit 68
fi
codesign --verify --deep --strict "$application_path"

if [[ -e "$previous_app" ]]; then
  rm -rf -- "$previous_app"
fi
install_changed=no

echo "安装完成：Prism $installed_version ($installed_build)"
echo "$application_path"
