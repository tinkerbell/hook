
IMG=lbdocker:5000/hwinfo:latest

build-image:
	docker build -t ${IMG} .

push-image:
	docker push ${IMG}

# WARN!!! don't run this on a real machine since the fio task will write to
# /dev/sda blindly and may corrupt your boot drive!!!!
#run-image:
#	docker run -it --rm --privileged \
#		-v /dev:/dev \
#		--net=host \
#		-e SELF_TEST_BASE_URL=http://build07:50070 \
#		-e MAC=0c:c4:7a:85:7d:d6 \
#		-e IP=192.168.16.174 \
#		-e ID=rack02-server75 \
#		${IMG}

