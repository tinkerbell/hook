default:
	mkdir -p out
	linuxkit build --docker -format kernel+initrd -name imho -dir out noname.yaml
