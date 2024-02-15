import zipfile,os

root_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),os.pardir)
adf_dir = r"K:\ROMS\Amiga\ADF\jotd"
adf_name = "DonkeyKong500.adf"

zip_out = os.path.join(root_dir,os.path.splitext(adf_name)[0]+"_adf.zip")

with zipfile.ZipFile(zip_out,"w",compression=zipfile.ZIP_DEFLATED) as zf:
    zf.write(os.path.join(adf_dir,adf_name),arcname=adf_name)
