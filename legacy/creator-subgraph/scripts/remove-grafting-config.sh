# requirements: jq

# enable errors
set -e

for configfile in ./config/*
do
  newjson="$(jq -r 'del(.grafting)' $configfile)"
  echo "$newjson"
  echo "$newjson" > $configfile
done
