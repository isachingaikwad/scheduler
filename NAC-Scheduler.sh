#!/bin/bash
set -e
set -o pipefail

START=$(date +%s)
export NACStackCreationFailed=301
{
	###  Define the image tag; Ex:IMAGE_TAG = nac-tf-202109
	IMAGE_TIME=$(date +'%Y%m%d') # => Image will create on Monthly basis
	# IMAGE_TIME=$(date +'%d%m%Y%H%M')
	# IMAGE_TAG="i-nac-tf"
	AWS_PROFILE=""
	AWS_REGION=""
	TFVARS_FILE=$1
	if [ ! -f "$TFVARS_FILE" ]; then
		echo "ERROR ::: Required TFVARS file is missing"
		exit 1
	else
		while IFS='=' read -r key value; do
			# key=$(echo $key | tr '.' '_')
			key=$(echo "$key")
			echo "key ::::: ${key} ~ ${value}"
			if [[ $(echo "${key}" | xargs) == "region" ]]; then
				AWS_REGION=$(echo "${value}" | xargs)
			fi
			if [[ $(echo "${key}" | xargs) == "aws_profile" ]]; then
				AWS_PROFILE=$(echo "${value}" | xargs)
				echo "$AWS_PROFILE"
				if [[ "$(aws configure list-profiles | grep "${AWS_PROFILE}")" == "" ]]; then
					echo "ERROR ::: AWS profile does not exists. To Create AWS PROFILE, Run cli command - aws configure "
					# exit 1
				# else
				# 	echo "INFO ::: AWS profile exists. CONTINUE . . . . . . . "
				# 	break
				fi
			fi

		done <"$TFVARS_FILE"
			if [[ $AWS_REGION == "" ]]; then
				echo "INFO ::: Append Required key region in TFVARS file"
				
			fi
			if [[ $AWS_PROFILE == "" ]]; then
				echo "ERROR ::: Required key aws_profile is missing in TFVARS file"
				exit 1
			fi
	fi
	IMAGE_TAG="nac-tf-${AWS_REGION}-$IMAGE_TIME"

	### Check for Home Directory Compatibility: WINDOWS and LINUX
	HOME_PATH=""
	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		HOME_PATH=$USERPROFILE
		echo "$HOME_PATH"
	else
		HOME_PATH=~/
	fi
	### Copy AWS configuration to current Directory
	AWS_CREDENTIAL_FILE="$HOME_PATH/.aws/credentials"
	AWS_CONFIG_FILE="$HOME_PATH/.aws/config"

	if [ ! -f "$AWS_CREDENTIAL_FILE" ] || [ ! -f "$AWS_CONFIG_FILE" ]; then
		echo "ERROR ::: Required AWS Congiguration files are missing. Run aws configure to setup aws profile"
		exit 1
	else
		cp -r "$HOME_PATH"/.aws ./.aws
		# cp $HOME_PATH/.aws/config ./.aws
		echo "INFO ::: AWS configuration copied to current Directory ${PWD}"

		AWS_ACCOUNT=$(eval aws sts get-caller-identity | jq -r ".Account")
		echo "INFO ::: AWS_ACCOUNT $AWS_ACCOUNT"

		AWS_DEFAULT_REGION=$(eval aws configure get region --profile "$AWS_PROFILE")
		echo "INFO ::: AWS_DEFAULT_REGION $AWS_DEFAULT_REGION"

	fi

	REPOSITORY="${AWS_ACCOUNT}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
	REPOSITORY_NAME="nct-nce-es"

	REPOSITORY_URL="$REPOSITORY/$REPOSITORY_NAME"
	echo "INFO ::: Login to AWS ECR Repo ::: ${REPOSITORY_URL}"

	COMMAND=$(aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${REPOSITORY_URL})
	echo "ECR ::: $COMMAND"
	# $COMMAND
	RES=$?
	echo $RES
	if [[ $RES -ne 0 ]]; then
		echo "ERROR ::: Login to AWS ECR FAILED. Status :::  $RES"
		exit 1
	else
		echo "INFO ::: Login to AWS ECR SUCCESS. Status :::  $RES"
	fi

	if ! docker info >/dev/null 2>&1; then
		echo "ERROR ::: This script uses docker, and it isn't running - please start docker and try again ! ! !"
		exit 1
	else
		echo "INFO ::: Docker running . . ! ! !"
	fi

	# private repository
	###DO NOT DELETE# aws ecr batch-get-image --repository-name="nct-nce-es" --image-ids=imageTag="nac-tf" --query 'images[].imageId.imageTag' --output text
	###DO NOT DELETE# aws ecr describe-images --repository-name="nct-nce-es" --image-ids=imageTag="nac-tf-hiu" 2> /dev/null | jq -r '.imageDetails[0].imageTags[0]'
	
	# ###  Command to check if image exists
	# COMMAND=$(docker image inspect ${REPOSITORY_URL}:nac-tf)
	COMMAND=$(docker image inspect "${REPOSITORY_URL}":"${IMAGE_TAG}")
	# echo $?
	if [ $? -ne 0 ]; then
		### Image Does not exist
		echo "WARN ::: Docker Image ${IMAGE_TAG} does not exist in ECR. So, Building a new Docker image..."
		COMMAND="docker build -t $REPOSITORY_NAME ." # WORKING
		$COMMAND
		echo $?
		if [ $? -eq 0 ]; then
			echo "INFO ::: Docker image Build SUCCESS !!!"
		else
			echo "INFO ::: Docker image Build FAILED."
			exit 1
		fi
		echo "INFO ::: Tagging Docker image as ${REPOSITORY_URL}:${IMAGE_TAG}"
		COMMAND="docker tag ${REPOSITORY_NAME}:latest ${REPOSITORY_URL}:${IMAGE_TAG}"
		$COMMAND
		echo "INFO ::: Pushing Docker image ${IMAGE_TAG} to ECR Repo :::  ${REPOSITORY_URL}"
		COMMAND="docker push ${REPOSITORY_URL}:${IMAGE_TAG}"
		$COMMAND
		# echo "INFO ::: Docker Push Status : $?"
		if [ $? -eq 0 ]; then
			echo "INFO ::: Docker image Push to ECR - SUCCESS"
		else
			echo "INFO ::: Docker image Push to ECR - FAILED ::: $COMMAND"
			exit 1
		fi
	else
		echo "INFO ::: Pulling Docker image ${IMAGE_TAG} from ECR Repo :::  ${REPOSITORY_URL}"
		COMMAND="docker pull ${REPOSITORY_URL}:${IMAGE_TAG}"
		$COMMAND
	fi
	### Construct unique Container Name, by taking imageTag and TFVARS File Name
	TFVARS_FILE_NAME=$(echo "$TFVARS_FILE" | cut -d'.' -f1)
	CONTAINER_NAME="con-${IMAGE_TAG}-${TFVARS_FILE_NAME}"
	COMMAND="docker run --rm -itd --name ${CONTAINER_NAME} ${REPOSITORY_URL}:${IMAGE_TAG} bash ./provision_nac.sh"
	echo "INFO ::: Run Docker Container ::: $COMMAND"
	$COMMAND
	COMMAND="docker cp $TFVARS_FILE ${CONTAINER_NAME}:./project/nac_es.tfvars"
	echo "INFO ::: Copy tfvars file to Docker Container ::: $COMMAND"
	$COMMAND
	COMMAND="docker cp ./.aws ${CONTAINER_NAME}:/root/"
	echo "INFO ::: Copy AWS Credential files to Docker Container /root/.aws/ folder ::: $COMMAND"
	$COMMAND
	
	sudo chmod 755 provision_nac.sh
	COMMAND="docker cp provision_nac.sh ${CONTAINER_NAME}:./project/provision_nac.sh"
	# COMMAND="docker cp provision_nac.sh ${CONTAINER_NAME}:./project/provision_nac.sh | chmod 755 provision_nac.sh"
	echo "INFO ::: Copy provision_nac.sh file to Docker Container ::: $COMMAND"
	$COMMAND

	# docker cp ./.aws container-nac-tf:/root/
	#######  Run the runContiner.sh
	# docker exec -it con-nac-tf bash -c ./runCon.sh
	echo "INFO ::: Execute script provision_nac.sh in Docker Container ::: ${CONTAINER_NAME}"
	COMMAND="docker exec -it ${CONTAINER_NAME} bash -c ./provision_nac.sh"
	$COMMAND
	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		echo "ERROR ::: Docker container creation :::  FAILED"
	else
		echo "INFO ::: NAC Stack container creation ::: SUCCESS"
	fi

	END=$(date +%s)
	secs=$((END - START))
	DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))
	echo "Total execution Time ::: $DIFF"
	exit 0

} || {
	echo "ERROR ::: Failed NAC Povisioning" && throw $NACStackCreationFailed

}

