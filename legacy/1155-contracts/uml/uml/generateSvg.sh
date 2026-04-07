#!/bin/sh
# converts all puml files to svg
# requires Docker to be installed and running

BASEDIR=$(dirname "$0")
# create output dir env var which is basedir/generated:
OUTPUT_DIR=$BASEDIR/generated
mkdir -p $OUTPUT_DIR
for FILE in $BASEDIR/*.puml; do
  echo Converting $FILE..
  FILE_SVG=${FILE//puml/svg}
  cat $FILE | docker run --rm -i think/plantuml > $FILE_SVG
  docker run --rm -v $PWD:/diagrams productionwentdown/ubuntu-inkscape inkscape /diagrams/$FILE_SVG --export-area-page --without-gui &> /dev/null
done
mv $BASEDIR/*.svg $OUTPUT_DIR 
echo Done