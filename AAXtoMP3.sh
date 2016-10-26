#!/usr/bin/env bash

TEMP_DIR=`mktemp -d -p /var/tmp`

trap "rm -rf ${TEMP_DIR};exit 1" INT 
trap "rm -rf ${TEMP_DIR};exit 0" EXIT

AUTHCODE=$1
shift
while [ $# -gt 0 ]; do
    FILE=$1
    echo "Decoding $FILE with AUTHCODE $AUTHCODE..."

    METADATA_FILE=${TEMP_DIR}/tmp.txt
    ffmpeg -i "$FILE" 2> ${METADATA_FILE}
    TITLE=`grep -a -m1 -h -r "title" ${METADATA_FILE} | head -1 | cut -d: -f2- | xargs -0`
    TITLE=`echo $TITLE | sed -e 's/(Unabridged)//' | xargs -0`
    # trim leading and trailing white space
    TITLE="$(echo -e "${TITLE}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    ARTIST=`grep -a -m1 -h -r "artist" ${METADATA_FILE} | head -1 | cut -d: -f2- | xargs`
    GENRE=`grep -a -m1 -h -r "genre" ${METADATA_FILE} | head -1 | cut -d: -f2- | xargs`
    BITRATE=`grep -a -m1 -h -r "bitrate" ${METADATA_FILE} | head -1 | rev | cut -d: -f 1 | rev | egrep -o [0-9]+ | xargs`
    BITRATE="${BITRATE}k"
    OUTPUT=`echo $TITLE | sed -e 's/\:/-/g' | xargs -0`
    # temp filename of single file generated from original aax file
    SINGLE_FILE=${TEMP_DIR}/$OUTPUT.mp3
    OUTPUT_DIR="${GENRE}/${TITLE}"

    ffmpeg -v error -stats -activation_bytes $AUTHCODE -i "${FILE}" -vn -c:a libmp3lame -ab $BITRATE "${SINGLE_FILE}"

    echo "Created ${SINGLE_FILE}."

    echo "Extracting chaptered mp3 files from ${SINGLE_FILE}..."
    mkdir -p "${OUTPUT_DIR}"
    keep_single_file=1
    while read -r first _ _ start _ end; do
        if [[ $first = Chapter ]]; then
            keep_single_file=0
            read
            read _ _ chapter
            chapter_num=`echo $chapter | awk '{print $2}'`
            if [ "$chapter_num" -lt 10 ] ; then
              chapter_num=`printf %02d $chapter_num`
            fi
            filename="${TEMP_DIR}/${OUTPUT} - Chapter $chapter_num.mp3"
            ffmpeg -v error -stats -i "${SINGLE_FILE}" -ss "${start%?}" -to "$end" -metadata title="Chapter $chapter_num"  -acodec copy "$filename" < /dev/null
            mv "$filename" "${OUTPUT_DIR}"
        fi
    done < ${METADATA_FILE}
    if [ "$keep_single_file" == "1" ] ; then
      mv "${SINGLE_FILE}" "${OUTPUT_DIR}"
      echo "Done creating chapters. Single file and chaptered files contained in ${OUTPUT_DIR}."
    else
      echo "Done creating chapters in ${OUTPUT_DIR}. Removing single file."
      rm "${SINGLE_FILE}"
    fi

    rm ${METADATA_FILE}

    echo "Extracting cover into ${OUTPUT_DIR}/cover.jpg..."
    ffmpeg -y -v error -activation_bytes $AUTHCODE -i "$FILE" -an -vcodec copy "${OUTPUT_DIR}/cover.jpg"
    echo "Done."

    shift
done
