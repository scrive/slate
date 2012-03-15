#!/bin/sh -e

# This script assumes the existence of BUILD_NUMBER from TeamCity
# This script assumes the existence of DIR as the path to the repo
# This script assumes TMP which is the directory as a temporary workspace
# example:
#DIR=/home/eric/haskell/kontrakcja

cd $DIR

BUILD_DATE=`date "+%Y-%m-%d-%H-%M-%S"`
BUILD_VCS_NUMBER=`git log -1 --pretty=oneline|awk '{print $1;}'`

sh build-scripts/runCleanCompile.sh

echo "Computing checksums of all binaries"

rm -rf checksums
mkdir checksums

find dist/build -executable -type f -exec sh -c 'sha512sum {} > checksums/`basename {}`.sha512' \;

echo "Running unit tests"
sh build-scripts/runAllUnitTests.sh > test-report.txt

BUILD_ID=$BUILD_DATE"."$BUILD_NUMBER"."$BUILD_VCS_NUMBER

ZIP=$BUILD_ID".production.tar.gz"

echo "Creating zip file"

tar zcf "$TMP/$ZIP"                   \
    --exclude=.git*                   \
    --exclude=_local*                 \
    --exclude=_darcs*                 \
    --exclude=_locakal_ticket_backup* \
    *
cd $TMP
ls -lh "$ZIP"

echo "Generating signature hash"
hashdoc=hash-$BUILD_ID.txt
m=`sha512sum "$ZIP" | awk 'BEGIN { FS = " +" } ; { print $1 }'`
echo "Scrive Production Build"         >  "$hashdoc"
echo "--------------------------------">> "$hashdoc"
echo "Build_ID:     $BUILD_ID"         >> "$hashdoc"
echo "Date:         $BUILD_DATE"       >> "$hashdoc"
echo "Build Number: $BUILD_NUMBER"     >> "$hashdoc"
echo "Commit ID:    $BUILD_VCS_NUMBER" >> "$hashdoc"
echo "Filename:     $ZIP"              >> "$hashdoc"
echo "SHA512SUM:    $m"                >> "$hashdoc"

echo ""                                 >> "$hashdoc"
echo "SHA512SUMS of Binaries"           >> "$hashdoc"
echo "--------------------------------" >> "$hashdoc"

cd $DIR
find dist/build -executable -type f -exec sha512sum {} \; >> "$TMP/$hashdoc"
cd $TMP
echo "------END------" >> "$hashdoc"

echo "Building soap request for Trustweaver signing"

echo "Multipart MIME"
mimefile=hash-$BUILD_ID.mime
python $DIR/scripts/genmime.py "$hashdoc" "$mimefile"

echo "Constructing SOAP Message"
soaprequest=request-$BUILD_ID.xml
base64 "$hashdoc" | cat $DIR/scripts/top - $DIR/scripts/bottom > "$soaprequest"

# For https authentication of Trustweaver
twcert=$DIR/certs/credentials.pem
twcertpwd=jhdaEo5LLejh
twurl=https://tseiod.trustweaver.com/ts/svs.asmx

echo "Signing with trustweaver"
soapresponse=response-$BUILD_ID.xml
curl -X POST --verbose --show-error                           \
    --cert $twcert:$twcertpwd --cacert $twcert                \
    --data-binary "@$soaprequest"                             \
    -H "Content-Type: text/xml; charset=UTF-8"                \
    -H "Expect: 100-continue"                                 \
    -H "SOAPAction: http://www.trustweaver.com/tsswitch#Sign" \
    -o "$soapresponse"                                        \
    $twurl

echo "Parsing XML response"
signed64=signed-$BUILD_ID.b64
python $DIR/scripts/parsesignresponse.py "$soapresponse" "$signed64"

echo "Decoding base64 response"
finalfile=$BUILD_ID.production.enhanced.tar.gz
signedmime=$BUILD_ID.signature.mime
base64 -d "$signed64" > "$signedmime"

echo "Creating final enhanced deployment file"
tar zcf "$finalfile" "$signedmime" "$ZIP"

echo "Pushing to amazon"
s3cmd --acl-private put "$finalfile" s3://kontrakcja-production

echo "Checking amazon md5 sum"
md5amazon=`s3cmd info "s3://kontrakcja-production/$finalfile" | grep MD5 | awk '{print $3}'`
echo "MD5SUM from Amazon S3: "$md5amazon
md5local=`md5sum "$finalfile" | awk 'BEGIN { FS = " +" } ; { print $1 }'`
echo "MD5SUM from local    : "$md5local
if [ "$md5amazon" = "$md5local" ]
then
    echo "MD5 sum matches!"
else
    echo "MD5 sum does not match. Please try again."
    exit 1
fi

echo "s3://kontrakcja-production/$finalfile"

exit 0
