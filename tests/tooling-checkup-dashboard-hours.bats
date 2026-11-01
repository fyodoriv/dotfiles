#!/usr/bin/env bats

@test "dashboard keeps 168 distinct UTC hours through spring and fall clock changes" {
  local root
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 - "$root" "$BATS_TEST_TMPDIR" <<'PY'
import datetime as dt
import importlib.util
from pathlib import Path
import sys
from zoneinfo import ZoneInfo

spec = importlib.util.spec_from_file_location("dashboard_export", Path(sys.argv[1]) / "skills/tooling-checkup/scripts/dashboard_export.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for month, day in ((3, 5), (10, 29)):
    start = dt.datetime(2026, month, day, tzinfo=dt.timezone.utc)
    samples = []
    for i in range(168):
        stamp = start + dt.timedelta(hours=i)
        local = stamp.astimezone(ZoneInfo("America/Toronto"))
        samples.append(f"{stamp.timestamp()}\t{local:%Y-%m-%dT%H:%M:%S}\t{i}\t1\t1\t10\t80\t0\t800")
    path = Path(sys.argv[2]) / f"{month}.tsv"
    path.write_text("\n".join(samples))
    rows = module.load_rows(path, (start + dt.timedelta(hours=168)).timestamp())
    assert len(rows) == 168, (month, len(rows))
    hours = [dt.datetime.fromisoformat(row["hour"].replace("Z", "+00:00")) for row in rows]
    assert all(hour.utcoffset() == dt.timedelta(0) for hour in hours), (month, "not UTC")
    assert len(set(hours)) == 168, month
    assert all((b - a).total_seconds() == 3600 for a, b in zip(hours, hours[1:])), month
    assert [row["peak_load1"] for row in rows] == list(range(168)), month
    print(f"{month}: 168 distinct UTC hours, ordered samples preserved")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
