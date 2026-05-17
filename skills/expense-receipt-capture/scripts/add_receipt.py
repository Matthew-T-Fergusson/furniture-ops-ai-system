#!/usr/bin/env python3
import argparse
import csv
import re
import shutil
from datetime import datetime
from pathlib import Path


def slugify(text: str) -> str:
    s = text.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")[:60] or "receipt"


def next_id(rows, date_str: str) -> str:
    y, m, d = date_str.split("-")
    prefix = f"R-{y}-{m}-{d}-"
    nums = []
    for r in rows:
        rid = (r.get("id") or "").strip()
        if rid.startswith(prefix):
            tail = rid[len(prefix):]
            if tail.isdigit():
                nums.append(int(tail))
    n = (max(nums) + 1) if nums else 1
    return f"{prefix}{n:03d}"


def ensure_header(path: Path):
    if path.exists() and path.stat().st_size > 0:
        with path.open(newline="", encoding="utf-8") as f:
            r = csv.DictReader(f)
            return r.fieldnames or []
    header = [
        "id",
        "date",
        "vendor",
        "amount",
        "currency",
        "category",
        "purpose",
        "file_path",
        "file_link",
        "notes",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=header)
        w.writeheader()
    return header


def main():
    p = argparse.ArgumentParser(description="Add a receipt record and copy image to repository")
    p.add_argument("--csv", required=True, help="Path to ledger CSV")
    p.add_argument("--source-image", required=True, help="Source image path")
    p.add_argument("--date", required=True, help="YYYY-MM-DD")
    p.add_argument("--vendor", required=True)
    p.add_argument("--amount", required=True)
    p.add_argument("--category", required=True)
    p.add_argument("--purpose", required=True)
    p.add_argument("--notes", default="")
    p.add_argument("--currency", default="USD")
    p.add_argument("--dest-dir", default="receipts/furniture-business-expenses")
    p.add_argument("--dest-name", default="", help="Optional filename override")
    args = p.parse_args()

    # Validate date
    datetime.strptime(args.date, "%Y-%m-%d")

    csv_path = Path(args.csv)
    source = Path(args.source_image)
    if not source.exists():
        raise SystemExit(f"Source image not found: {source}")

    header = ensure_header(csv_path)

    rows = []
    with csv_path.open(newline="", encoding="utf-8") as f:
        r = csv.DictReader(f)
        rows = list(r)

    rid = next_id(rows, args.date)

    dest_dir = Path(args.dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    if args.dest_name:
        dest_name = args.dest_name
    else:
        vendor_slug = slugify(args.vendor)
        ext = source.suffix.lower() or ".jpg"
        dest_name = f"{args.date}_receipt_{vendor_slug}{ext}"

    dest = dest_dir / dest_name
    if dest.exists():
        # Avoid collision
        stem = dest.stem
        ext = dest.suffix
        i = 2
        while True:
            cand = dest_dir / f"{stem}_{i}{ext}"
            if not cand.exists():
                dest = cand
                break
            i += 1

    shutil.copy2(source, dest)

    file_path = str(dest).replace("\\", "/")
    if file_path.startswith("./"):
        file_path_rel = file_path[2:]
    else:
        file_path_rel = file_path

    # If absolute under cwd, make relative
    cwd = Path.cwd().resolve()
    try:
        rel = Path(file_path_rel).resolve().relative_to(cwd)
        file_path_rel = str(rel).replace("\\", "/")
    except Exception:
        pass

    row = {
        "id": rid,
        "date": args.date,
        "vendor": args.vendor,
        "amount": str(args.amount),
        "currency": args.currency,
        "category": args.category,
        "purpose": args.purpose,
        "file_path": file_path_rel,
        "file_link": f"./{file_path_rel}",
        "notes": args.notes,
    }

    # Ensure row uses existing header order
    out = {k: row.get(k, "") for k in header}
    rows.append(out)

    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=header)
        w.writeheader()
        w.writerows(rows)

    print(f"Logged {rid}")
    print(f"Saved image: {file_path_rel}")


if __name__ == "__main__":
    main()
