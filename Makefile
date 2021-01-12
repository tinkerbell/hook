default: bootkitBuild tink-dockerBuild image

image:
	mkdir -p out
	linuxkit build --docker -format kernel+initrd -name imho -dir out noname.yaml

run:
	sudo ~/go/bin/linuxkit run qemu --mem 2048 out/imho

bootkitBuild:
	cd bootkit; docker buildx build  --platform linux/amd64 --load -t bootkit:0.0 .

tink-dockerBuild:
	cd tink-docker; docker buildx build  --platform linux/amd64 --load -t tink-docker:0.0 .