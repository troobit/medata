#!/usr/bin/env python3
"""Register App/*.swift files in MeData.xcodeproj (the four-place checklist).

`App/` is not a filesystem-synchronised group, so every file needs a
PBXBuildFile, a PBXFileReference, a PBXGroup child entry and a
PBXSourcesBuildPhase entry. Miss one and the build either fails or silently
omits the file (docs/agent-notes/ui-capture-flow.md).

Each new file's entries are inserted beside the anchor file's, and its ids are
derived from its name, so a re-run is a no-op and produces no diff churn.

    python3 tools/pbx_add_app_file.py FieldNote.swift FieldNoteSheet.swift
"""
import hashlib
import pathlib
import sys

PBX = pathlib.Path(__file__).resolve().parents[1] / "MeData/MeData.xcodeproj/project.pbxproj"
ANCHOR = "MealReviewView.swift"


def ident(name, salt):
    return hashlib.sha1(f"{salt}:{name}".encode()).hexdigest()[:24].upper()


def insert_after(text, predicate, new_line):
    line = next(l for l in text.splitlines() if predicate(l))
    return text.replace(line + "\n", line + "\n" + new_line + "\n", 1)


def add(text, name, anchor_file_id, anchor_build_id):
    if f"/* {name} */" in text:
        return text, False
    build_id, file_id = ident(name, "build"), ident(name, "file")
    text = insert_after(
        text,
        lambda l: f"/* {ANCHOR} in Sources */ = {{isa = PBXBuildFile" in l,
        f"\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};")
    text = insert_after(
        text,
        lambda l: f"/* {ANCHOR} */ = {{isa = PBXFileReference" in l,
        f"\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {name}; path = ../App/{name}; sourceTree = SOURCE_ROOT; }};")
    text = insert_after(
        text,
        lambda l: l.strip() == f"{anchor_file_id} /* {ANCHOR} */,",
        f"\t\t\t\t{file_id} /* {name} */,")
    text = insert_after(
        text,
        lambda l: l.strip() == f"{anchor_build_id} /* {ANCHOR} in Sources */,",
        f"\t\t\t\t{build_id} /* {name} in Sources */,")
    return text, True


def main():
    text = PBX.read_text()
    anchor_file_id = next(l.split()[0] for l in text.splitlines()
                          if f"/* {ANCHOR} */ = {{isa = PBXFileReference" in l)
    anchor_build_id = next(l.split()[0] for l in text.splitlines()
                           if f"/* {ANCHOR} in Sources */ = {{isa = PBXBuildFile" in l)
    added = []
    for name in sys.argv[1:]:
        text, did = add(text, name, anchor_file_id, anchor_build_id)
        if did:
            added.append(name)
    PBX.write_text(text)
    print("added=" + (",".join(added) if added else "none"))


if __name__ == "__main__":
    main()
