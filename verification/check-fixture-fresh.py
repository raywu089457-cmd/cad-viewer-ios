"""Checks that the committed snapshot still matches what the pipeline produces.

The snapshot is produced once and committed, which is what makes the independent coordinate
check possible without a Swift toolchain. It also means the two can drift: the check would go
on passing against a stale copy of its own expected output.

Compared as geometry rather than as bytes. The committed snapshot came from a wasm build and
CI produces a native Linux one; both are the same geometry, but the two Foundations format
doubles differently.

    python3 check-fixture-fresh.py <fresh.json> <committed.json>
"""
import json
import sys


def points(scene):
    return [
        [(point["x"], point["y"]) for point in line["points"]]
        for line in scene["polylines"]
    ]


def main(fresh_path, committed_path):
    with open(fresh_path) as handle:
        fresh = json.load(handle)
    with open(committed_path) as handle:
        committed = json.load(handle)

    a, b = points(fresh), points(committed)
    if len(a) != len(b):
        print(f"polyline count differs: {len(a)} fresh, {len(b)} committed")
        return 1

    for index, (fresh_line, committed_line) in enumerate(zip(a, b)):
        if len(fresh_line) != len(committed_line):
            print(
                f"polyline {index} has {len(fresh_line)} points, "
                f"committed has {len(committed_line)}"
            )
            return 1
        for position, ((x1, y1), (x2, y2)) in enumerate(zip(fresh_line, committed_line)):
            if abs(x1 - x2) > 1e-6 or abs(y1 - y2) > 1e-6:
                print(
                    f"polyline {index} point {position}: "
                    f"({x1}, {y1}) fresh, ({x2}, {y2}) committed"
                )
                return 1

    print("the fixture snapshot is current")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: check-fixture-fresh.py <fresh.json> <committed.json>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
