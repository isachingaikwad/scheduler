#!/bin/bash
set -e
set -o pipefail
cleanup() {
            exitcode=$?
            printf 'error condition hit\n' 1>&2
            printf 'exit code returned: %s\n' "$exitcode"
            printf 'the command executing at the time of the error was: %s\n' "$BASH_COMMAND"
            printf 'command present on line: %d' "${BASH_LINENO[0]}"
            # Some more clean up code can be added here before exiting
            exit $exitcode
         }
START=$(date +%s)
export NACStackCreationFailed=301
{
###  Define the image tag
	IMAGE_TIME=$(date +'%Y%m')  # => Image will create on Monthly basis
	# IMAGE_TIME=$(date +'%d%m%Y%H%M')
	IMAGE_TAG="nac-tf-$IMAGE_TIME"
	AWS_PROFILE=""
	TFVARS_FILE=$1
	if [ ! -f "$TFVARS_FILE" ]; then
		echo "ERROR ::: Required TFVARS file is missing"
		exit 1
	else
		#   echo "$TFVARS_FILE found."
		while IFS='=' read -r key value; do
			# key=$(echo $key | tr '.' '_')
			key=$(echo $key)
			# eval ${key}=\${value}
			# echo "${key} ::::: ${value}"
			if [[ $key == "aws_profile" ]]; then
				AWS_PROFILE=$value
				# echo $AWS_PROFILE
				if [[ "eval $(aws configure list-profiles | grep ${AWS_PROFILE})" == "" ]]; then
					echo "ERROR ::: AWS profile does not exists. To Create AWS PROFILE, Run cli command - aws configure "
					exit 0
				else
					echo "INFO ::: AWS profile exists. CONTINUE . . . . . . . "
					break
				fi
			fi
		done <"$TFVARS_FILE"
	fi

	### Download Provisioning Code from GitHub

	# COMMAND="git clone -b main https://github.com/psahuNasuni/nac-es.git"
	# $COMMAND
	# RESULT=$?
	# if [ $RESULT -eq 0 ]; then
	# 	echo "INFO ::: git clone success"
	# else
	# 	COMMAND="cd nac-es && git pull origin main"
	# 	$COMMAND
	# fi

	############################################

	### Check for Home Directory Compatibility: WINDOWS and LINUX
	HOME_PATH=""
	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		HOME_PATH=$USERPROFILE
		echo $HOME_PATH
	else
		HOME_PATH=$HOME
	fi
	### Copy AWS configuration to current Directory
	AWS_CREDENTIAL_FILE="$HOME_PATH/.aws/credentials"
	AWS_CONFIG_FILE="$HOME_PATH/.aws/config"

	if [ ! -f "$AWS_CREDENTIAL_FILE" ] || [ ! -f "$AWS_CONFIG_FILE" ]; then
		echo "ERROR ::: Required AWS Congiguration files are missing. Run aws configure to setup aws profile"
		exit 1
	else
		echo "INFO ::: Copying AWS configuration to current Directory"
		cp -r $HOME_PATH/.aws ./.aws
		# cp $HOME_PATH/.aws/config ./.aws

		AWS_ACCOUNT=$(eval aws sts get-caller-identity | jq -r ".Account")
		echo $AWS_ACCOUNT

		AWS_DEFAULT_REGION=$(eval aws configure get region --profile $AWS_PROFILE)
		echo $AWS_DEFAULT_REGION

	fi

	REPOSITORY="${AWS_ACCOUNT}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
	REPOSITORY_NAME="nct-nce-es"

	REPOSITORY_URL="$REPOSITORY/$REPOSITORY_NAME"

	### NEED Login to AWS ECR for ECR pull
	if [ aws ecr get-login help ] &>/dev/null; then
		COMMAND="eval $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email)"
	else
		COMMAND="$(aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $REPOSITORY_URL)"
	fi
	echo "$COMMAND"
	# aws sts get-caller-identity
	RES=$?
	echo $RES
	if [[ $RES -ne 0 ]]; then
		echo "ERROR ::: Login to AWS ECR FAILED with Status :  $RES"
		exit 1
	else
		echo "INFO ::: Login to AWS ECR SUCCESS with Status :::  $RES"
	fi
	# echo "ECR Login Success "

	if ! docker info >/dev/null 2>&1; then
		echo "ERROR ::: This script uses docker, and it isn't running - please start docker and trygain a!"
		exit 1
	fi

	# ###  Command to check if image exists
	COMMAND="docker inspect ${REPOSITORY_URL}:${IMAGE_TAG}"
	###  Run the command then check the status code
	$COMMAND

} || {
	echo "ERROR ::: Failed NAC Povisioning" && throw $NACStackCreationFailed

}