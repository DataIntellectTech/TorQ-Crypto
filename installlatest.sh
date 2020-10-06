#!/bin/bash

#example usage:
#bash installlatest.sh

get_latest_release() {
	curl --silent "https://api.github.com/repos/$1/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")'
}

wget https://raw.githubusercontent.com/AquaQAnalytics/TorQ/master/installtorqapp.sh

torq_latest=`get_latest_release "AquaQAnalytics/TorQ"`

if [[  $torq_latest == *?.?.? ]] || [[  $torq_latest == *?.??.?? ]];
then
        echo "============================================================="
	echo "Latest TorQ release"
	echo $torq_latest
	echo "Getting the latest TorQ .tar.gz file"
	echo "============================================================="

	
else
	echo "the tag for Torq release: "
        echo $torq_latest
        echo "Is not in the right format, exiting script."
	exit 1
fi

wget --content-disposition https://github.com/AquaQAnalytics/TorQ/archive/$torq_latest.tar.gz

echo $torq_latest

if [ "${torq_latest%%v*}" ]
then
  echo "tag doesn't start with v"
else
  torq_latest=${torq_latest#?}
fi

echo $torq_latest

torq_crypto_latest=`get_latest_release "AquaQAnalytics/TorQ-Crypto"`

echo "============================================================="
echo "Latest TorQ-Crypto release"
echo $torq_crypto_latest
echo "Getting the latest TorQ-Crypto .tar.gz file"
echo "============================================================="

if [[  $torq_crypto_latest == *?.?.? ]] || [[  $torq_crypto_latest == *?.??.?? ]];
then
	echo "============================================================="
	echo "Latest TorQ-Crypto release"
	echo $torq_crypto_latest
	echo "Getting the latest TorQ-Crypto .tar.gz file"
	echo "============================================================="

	
else
        echo "the tag for Torq release: "
        echo $torq_crypto_latest
        echo "Is not in the right format, exiting script."
	exit 1
fi


wget --content-disposition https://github.com/AquaQAnalytics/TorQ-Crypto/archive/$torq_crypto_latest.tar.gz

echo $torq_crypto_latest

if [ "${torq_crypto_latest%%v*}" ]
then
  echo "tag doesn't start with v"
else
  torq_crypto_latest=${torq_crypto_latest#?}
fi

echo $torq_crypto_latest

echo "Files downloaded. Executing install script"

bash installtorqapp.sh --torq TorQ-$torq_latest.tar.gz --releasedir deploy --data datatemp --installfile TorQ-Crypto-$torq_crypto_latest.tar.gz
