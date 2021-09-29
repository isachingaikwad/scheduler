#!/bin/bash
set -e
set -o pipefail

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
		exit 0
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
		COMMAND="$(aws ecr get-login-password | docker login --username AWS --password-stdin $REPOSITORY_URL)"
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
	RESULT_IMAGE_EXISTS=$?
	if [ $RESULT_IMAGE_EXISTS -ne 0 ]; then
		### Image did not exist
		echo "IMAGE ${IMAGE_TAG} does not exist in ECR Repo. So, Building a new Docker image..."
		COMMAND="docker build -t $REPOSITORY_NAME ." # WORKING
		# COMMAND="docker build -t $REPOSITORY_URL:$IMAGE_TAG ."
		$COMMAND
		echo "INFO ::: BUILD SUCCESS - Docker image ::: $COMMAND"

		echo "INFO ::: Tagging Docker image. . . . . . . . . . . . . . ."
		COMMAND="docker tag ${REPOSITORY_NAME}:latest ${REPOSITORY_URL}:${IMAGE_TAG}"
		$COMMAND
		echo "INFO ::: Pushing Docker image ${IMAGE_TAG} to ECR Repo :::  ${REPOSITORY_URL}"
		COMMAND="docker push ${REPOSITORY_URL}:${IMAGE_TAG}"
		$COMMAND
		echo "INFO ::: Successfully Pushed Docker image to ECR ::: $COMMAND"
	else
		### Image exists already
		echo "WARNING ::: Docker image ${IMAGE_TAG} already exists in ECR repo ::: ${REPOSITORY_URL}"
	fi
	# COMMAND="docker run --rm -it ${REPOSITORY_URL}:${IMAGE_TAG} bash"
	COMMAND="docker system prune -a -f"
	$COMMAND
	COMMAND="docker run --rm -itd --name con-${IMAGE_TAG} ${REPOSITORY_URL}:${IMAGE_TAG} bash"
	# COMMAND="docker run --rm -it -v ./project/${TFVARS_FILE} ${REPOSITORY_URL}:${IMAGE_TAG} bash"
	echo "INFO ::: RUN Docker Container ::: $COMMAND"
	$COMMAND
	COMMAND="docker cp $TFVARS_FILE con-${IMAGE_TAG}:./project/$TFVARS_FILE"
	echo "INFO ::: Copy tfvars file to Docker Container ::: $COMMAND"
	$COMMAND
	COMMAND="docker cp ./.aws con-${IMAGE_TAG}:/root/"
	echo "INFO ::: Copy AWS Credential files to Docker Container /root/.aws/ folder ::: $COMMAND"
	$COMMAND
	# docker cp ./.aws container-nac-tf:/root/
	#######  Run the runContiner.sh
	# docker exec -it con-nac-tf bash -c ./runCon.sh
	echo "INFO ::: Execute script runCon.sh in Docker Container ::: con-${IMAGE_TAG}"
	COMMAND="docker exec -it con-${IMAGE_TAG} bash -c ./runCon.sh"
	$COMMAND
	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		echo "ERROR ::: Docker container creation :::  FAILED"
	else
		echo "INFO ::: Docker container creation ::: SUCCESS"
	fi

	END=$(date +%s)
	DIFF=$(( $END - $START ))
	echo "Total execution Time ::: $DIFF seconds"
	exit 0

} || {
	echo "ERROR ::: Failed NAC Povisioning" && throw $NACStackCreationFailed

}

# docker run --rm -it -v "config:/awscre/config" akak:latest bash

# docker run --rm -it -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} akak:latest bash
# docker run --rm -it -e AWS_ACCESS_KEY_ID=pkAWS_ACCESS_KEY -e AWS_SECRET_ACCESS_KEY=pkAWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=pktrgion akak:latest bash
# docker run --rm -it -e AWS_ACCESS_KEY_ID=pkAWS_ACCESS_KEY -e AWS_SECRET_ACCESS_KEY=pkAWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION=pktrgion 514960042727.dkr.ecr.us-east-1.amazonaws.com/nct-nce-es:nac-tf /bin/bash

# docker run --rm -it -v ./project/user.tfvars -v /root/.aws/credentials 514960042727.dkr.ecr.us-east-1.amazonaws.com/nct-nce-es:nac-tf bash

# aws ecr get-login-password | docker login --username AWS --password-stdin 514960042727.dkr.ecr.us-east-1.amazonaws.com/nct-nce-es:nac-tf

# docker run --rm -itd --name container-nac-tf 514960042727.dkr.ecr.us-east-1.amazonaws.com/nct-nce-es:nac-tf bash
# docker cp user.tfvars container-nac-tf:./project/user.tfvars
# docker cp ./.aws container-nac-tf:/root/
