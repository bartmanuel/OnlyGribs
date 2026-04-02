import sys
from eccodes import *

#INPUT = "KNMI43HumidityFraction.grib"
#OUTPUT = "KNMI43Humidity.grib"

def main(input_file, output_file):
    with open(input_file, "rb") as fin, open(output_file, "wb") as fout:
        while True:
            try:
                gid = codes_grib_new_from_file(fin)
                if gid is None:
                    break

                values = codes_get_array(gid, "values")
                values = [v * 100 for v in values]
                codes_set_values(gid, values)

                codes_write(gid, fout)
                codes_release(gid)
            except Exception as e:
                print(f"Error: {e}", file=sys.stderr)
                break

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 ScaleFraction.py input.grib output.grib")
        sys.exit(1)

    main(sys.argv[1], sys.argv[2])        
#    main(INPUT, OUTPUT)        