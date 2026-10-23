#!/usr/bin/env python3
"""Replace local SVG <use> references in bundled flags with concrete shapes.

AppKit's SVG renderer omits some referenced shapes, leaving flags such as CN
without their emblems. This is a one-time asset normalization tool; it is
idempotent and does not add a runtime dependency to Prism.
"""

from pathlib import Path
from xml.dom import minidom


RESOURCES = Path(__file__).resolve().parent.parent / "Prism/Resources"
FLAG_DIRECTORIES = ("SquareFlags", "FlagKitFlags")
SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"


def expand_flag(path: Path) -> bool:
    document = minidom.parse(str(path))
    definitions = {
        element.getAttribute("id"): element
        for element in document.getElementsByTagName("*")
        if element.hasAttribute("id")
    }
    if not document.getElementsByTagNameNS(SVG_NS, "use"):
        return False

    def expand(node, ancestors: tuple[str, ...] = ()) -> None:
        for child in list(node.childNodes):
            if child.nodeType != child.ELEMENT_NODE:
                continue
            if child.namespaceURI != SVG_NS or child.localName != "use":
                expand(child, ancestors)
                continue

            href = child.getAttributeNS(XLINK_NS, "href") or child.getAttribute("href")
            if not href.startswith("#") or href[1:] not in definitions:
                raise ValueError(f"{path.name}: unresolved SVG reference {href!r}")
            target_id = href[1:]
            if target_id in ancestors:
                raise ValueError(f"{path.name}: cyclic SVG reference {target_id!r}")

            group = document.createElementNS(SVG_NS, "g")
            for index in range(child.attributes.length):
                attribute = child.attributes.item(index)
                if attribute.localName not in ("href", "width", "height", "x", "y"):
                    group.setAttributeNS(attribute.namespaceURI, attribute.name, attribute.value)

            x = child.getAttribute("x") or "0"
            y = child.getAttribute("y") or "0"
            placement = document.createElementNS(SVG_NS, "g") if x != "0" or y != "0" else group
            if placement is not group:
                placement.setAttribute("transform", f"translate({x} {y})")
                group.appendChild(placement)
            clone = definitions[target_id].cloneNode(deep=True)
            holder = document.createElementNS(SVG_NS, "g")
            holder.appendChild(clone)
            expand(holder, ancestors + (target_id,))
            for expanded_child in list(holder.childNodes):
                placement.appendChild(expanded_child)
            node.replaceChild(group, child)

    expand(document.documentElement)
    if document.getElementsByTagNameNS(SVG_NS, "use"):
        raise ValueError(f"{path.name}: unexpanded SVG reference")
    path.write_bytes(document.toxml(encoding="utf-8"))
    return True


def main() -> None:
    changed = [
        path.name
        for directory in FLAG_DIRECTORIES
        for path in sorted((RESOURCES / directory).glob("*.svg"))
        if expand_flag(path)
    ]
    print(f"Expanded SVG references in {len(changed)} flags")


if __name__ == "__main__":
    main()
