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

convert:
	mkdir convert
	cp out/imho-initrd.img ./convert/initrd.gz
	cd convert; gunzip ./initrd.gz; cpio -idv < initrd; rm initrd; find . -print0 | cpio --null -ov --format=newc > ../initramfs; gzip ../initramfs

