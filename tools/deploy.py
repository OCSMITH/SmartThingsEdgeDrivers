import os, subprocess, requests, json, time, yaml, hashlib

BRANCH = os.environ.get('BRANCH')
ENVIRONMENT = os.environ.get('ENVIRONMENT')
print(BRANCH)
print(ENVIRONMENT)
branch_environment = "{}_{}_".format(BRANCH, ENVIRONMENT)
ENVIRONMENT_URL = os.environ.get(ENVIRONMENT+'_ENVIRONMENT_URL')
UPLOAD_URL = ENVIRONMENT_URL+"/drivers/package"
CHANNEL_ID = os.environ.get(branch_environment+'CHANNEL_ID')
if not CHANNEL_ID:
  print("No channel id specified, aborting.")
  exit(0)

UPDATE_URL = ENVIRONMENT_URL+"/channels/"+CHANNEL_ID+"/drivers/bulk"
TOKEN = os.environ.get(ENVIRONMENT+'_TOKEN')
DRIVERID = "driverId"
VERSION = "version"
ARCHIVEHASH = "archiveHash"
PACKAGEKEY = "packageKey"

BOSE_APPKEY = os.environ.get("BOSE_AUDIONOTIFICATION_APPKEY")

print(ENVIRONMENT_URL)

# Make sure we're running in the root of the git directory
a = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True)
os.chdir(a.stdout.decode().strip()+"/drivers/SmartThings/")

# Get list of all SmartThings driver folders
drivers = [driver.name for driver in os.scandir('.') if driver.is_dir()]
driver_updates = []
drivers_updated = []
uploaded_drivers = {}

# Get drivers currently on the channel
response = requests.get(
  ENVIRONMENT_URL+"/channels/"+CHANNEL_ID+"/drivers",
  headers={
    "Accept": "application/vnd.smartthings+json;v=20200810",
    "Authorization": "Bearer "+TOKEN,
    "X-ST-LOG-LEVEL": "TRACE"
  }
)
if response.status_code != 200:
  print("Failed to retrieve channel's current drivers")
  print("Error code: "+str(response.status_code))
  print("Error response: "+response.text)
else:
  response_json = json.loads(response.text)["items"]
  for driver in response_json:
    # get detailed driver info for currently-uploaded drivers
    driver_info_response = requests.post(
      ENVIRONMENT_URL+"/drivers/search",
      headers = {
        "Accept": "application/vnd.smartthings+json;v=20200810",
        "Authorization": "Bearer "+TOKEN,
        "X-ST-LOG-LEVEL": "TRACE"
      },
      json = {
        DRIVERID: driver[DRIVERID],
        "driverVersion": driver[VERSION]
      }
    )
    driver_info_response_json = json.loads(driver_info_response.text)["items"][0]
    if PACKAGEKEY in driver_info_response_json:
      archiveHash = driver_info_response_json[ARCHIVEHASH]
      packageKey = driver_info_response_json[PACKAGEKEY]
      if VERSION in driver.keys() and DRIVERID in driver.keys():
        uploaded_drivers[packageKey] = {DRIVERID: driver[DRIVERID], VERSION: driver[VERSION], ARCHIVEHASH: archiveHash}

# For each driver, first package the driver locally, then upload it
# after it's been uploaded, hold on to the driver id and version
for driver in drivers:
  subprocess.run(["rm", "edge.zip"], capture_output=True)
  package_key = ""
  with open(driver+"/config.yml", 'r') as config_file:
    package_key = yaml.safe_load(config_file)["packageKey"]
    print(package_key)
  if package_key == "bose" and BOSE_APPKEY:
    # write the app key into a app_key.lua (overwrite if exists already)
    subprocess.run(["touch -a ./src/app_key.lua && echo \'return \"" + BOSE_APPKEY +  "\"\n\' > ./src/app_key.lua"], cwd=driver, shell=True, capture_output=True)
  subprocess.run(["zip -r ../edge.zip config.yml fingerprints.yml $(find profiles -name \"*.y*ml\") $(find . -name \"*.lua\") -x \"*test*\""], cwd=driver, shell=True,  capture_output=True)
  with open("edge.zip", 'rb') as driver_package:
    data = driver_package.read()
    # TODO: This does not yet work, hash returned by server does not match
    hash = hashlib.sha256(data).hexdigest()
    response = None
    retries = 0
    if package_key not in uploaded_drivers or hash != uploaded_drivers[package_key][ARCHIVEHASH]:
      while response == None or (response.status_code == 500 or response.status_code == 429):
        response = requests.post(
          UPLOAD_URL,
          headers={
            "Content-Type": "application/zip",
            "Accept": "application/vnd.smartthings+json;v=20200810",
            "Authorization": "Bearer "+TOKEN,
            "X-ST-LOG-LEVEL": "TRACE"},
          data=data)
        if response.status_code != 200:
          print("Failed to upload driver "+driver)
          print("Error code: "+str(response.status_code))
          print("Error response: "+response.text)
          if response.status_code == 500 or response.status_code == 429:
            retries = retries + 1
            if retries > 3:
              break # give up
            if response.status_code == 429:
              time.sleep(10)
        else:
          print("Uploaded package successfully: "+driver)
          drivers_updated.append(driver)
          response_json = json.loads(response.text)
          uploaded_drivers[package_key] = {DRIVERID: response_json[DRIVERID], VERSION: response_json[VERSION], ARCHIVEHASH: hash}
    elif hash == uploaded_drivers[package_key][ARCHIVEHASH]:
      print("Hash matched existing driver for "+package_key)
      print(hash)
      print(uploaded_drivers[package_key][ARCHIVEHASH])
      # hash matched, use the currently uploaded version of the driver to "update" the channel

for package_key, driver_info in uploaded_drivers.items():
  print("Uploading package: {} driver id: {} version: {}".format(package_key, driver_info[DRIVERID], driver_info[VERSION]))
  driver_updates.append({DRIVERID: driver_info[DRIVERID], VERSION: driver_info[VERSION]})

response = requests.put(
  UPDATE_URL,
  headers={
    "Accept": "application/vnd.smartthings+json;v=20200810",
    "Authorization": "Bearer "+TOKEN,
    "Content-Type": "application/json",
    "X-ST-LOG-LEVEL": "TRACE"
  },
  data=json.dumps(driver_updates)
)
if response.status_code != 204:
  print("Failed to bulk update drivers")
  print("Error code: "+str(response.status_code))
  print("Error response: "+response.text)
  exit(1)

print("Successfully bulk-updated channel: ")
print(drivers_updated)
print("\nDrivers currently deplpyed: ")
print(uploaded_drivers.keys())