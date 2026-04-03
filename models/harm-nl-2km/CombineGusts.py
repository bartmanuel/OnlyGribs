import sys
import math
import eccodes

def read_values(filepath, param_id):
    values = []
    handles = []

    with open(filepath, 'rb') as f:
        while True:
            gid = eccodes.codes_grib_new_from_file(f)
            if gid is None:
                break
            param = eccodes.codes_get(gid, "indicatorOfParameter")
            if param == param_id:
                handles.append(gid)
                values.append(eccodes.codes_get_array(gid, "values"))
            else:
                eccodes.codes_release(gid)

    return handles, values

def main(u_file, v_file, output_file):
    u_handles, u_values_list = read_values(u_file, 162)
    v_handles, v_values_list = read_values(v_file, 163)

    if len(u_values_list) != len(v_values_list):
        print("Mismatch in number of messages between U and V files")
        sys.exit(1)

    with open(output_file, 'wb') as out_f:
        for u_gid, v_gid, u_vals, v_vals in zip(u_handles, v_handles, u_values_list, v_values_list):
            if len(u_vals) != len(v_vals):
                print("Mismatch in array size between U and V components.")
                continue

            # Calculate combined gust magnitude
            combined = [math.sqrt(u**2 + v**2) for u, v in zip(u_vals, v_vals)]

            # Clone from U-component
            new_gid = eccodes.codes_clone(u_gid)

            # Set new parameter ID
            eccodes.codes_set(new_gid, "indicatorOfParameter", 180)  # param 180 = wind gust

            # Optional: set a name
            # eccodes.codes_set(new_gid, "name", "Wind gust combined")
            # eccodes.codes_set(new_gid, "shortName", "gust")
            eccodes.codes_set(new_gid, "typeOfLevel", "surface")
            eccodes.codes_set(new_gid, "level", 0)  

            # Set new values
            eccodes.codes_set_values(new_gid, combined)

            # Write to output
            eccodes.codes_write(new_gid, out_f)

            # Cleanup
            eccodes.codes_release(u_gid)
            eccodes.codes_release(v_gid)
            eccodes.codes_release(new_gid)

    print(f"Output written to {output_file}")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python3 CombineGusts.py u_file.grib v_file.grib output.grib")
        sys.exit(1)

    main(sys.argv[1], sys.argv[2], sys.argv[3])