"""
Combines the eastward (10efg) and northward (10nfg) gust components
from a single GRIB2 file into a scalar gust magnitude (sqrt(u²+v²)).
The output message is cloned from the 10efg message with updated values.

Usage: python3 CombineGusts_GRIB2.py input_gust_uv.grib2 output_gusts.grib2
"""
import math
import sys
import eccodes


def read_by_shortname(filepath, shortname):
    handles, values = [], []
    with open(filepath, "rb") as f:
        while True:
            gid = eccodes.codes_grib_new_from_file(f)
            if gid is None:
                break
            if eccodes.codes_get(gid, "shortName") == shortname:
                handles.append(gid)
                values.append(eccodes.codes_get_array(gid, "values"))
            else:
                eccodes.codes_release(gid)
    return handles, values


def main(input_file, output_file):
    u_handles, u_values = read_by_shortname(input_file, "10efg")
    v_handles, v_values = read_by_shortname(input_file, "10nfg")

    if len(u_values) != len(v_values):
        print(f"Mismatch: {len(u_values)} 10efg vs {len(v_values)} 10nfg messages")
        sys.exit(1)

    with open(output_file, "wb") as out_f:
        for u_gid, v_gid, u_vals, v_vals in zip(u_handles, v_handles, u_values, v_values):
            magnitude = [math.sqrt(u**2 + v**2) for u, v in zip(u_vals, v_vals)]
            new_gid = eccodes.codes_clone(u_gid)
            eccodes.codes_set_values(new_gid, magnitude)
            eccodes.codes_write(new_gid, out_f)
            eccodes.codes_release(u_gid)
            eccodes.codes_release(v_gid)
            eccodes.codes_release(new_gid)

    print(f"Output written to {output_file}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 CombineGusts_GRIB2.py input_gust_uv.grib2 output_gusts.grib2")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
