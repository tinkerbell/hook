default:
	mkdir -p out
	linuxkit build -format kernel+initrd -name imho -dir out noname.yaml
