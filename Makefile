BASE_IMAGE=debian:stretch
CMK_VERSION=1.5.0p7
GCC_VERSION=7.3.0
DOCKER_HUB_USER=msperl
DEB_RELEASE=stretch
ARCH=arm
PARALLEL_BUILD=$(shell grep -c "^processor" /proc/cpuinfo)

all: base gcc cmk_deb check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/all.tar.gz cmk_docker_image
push: push_base push_gcc push_cmk_deb push_cmk_img

PHONY: base
base:
	docker build . \
	  -t check_mk-build-base:$(DEB_RELEASE)-$(ARCH) \
	  -f Dockerfile.base \
	  --build-arg DEB_RELEASE=$(DEB_RELEASE)

PHONY: push_base
push_base: base
	docker tag \
	  check_mk-build-base:$(DEB_RELEASE)-$(ARCH) \
	  $(DOCKER_HUB_USER)/check_mk-build-base:$(DEB_RELEASE)-$(ARCH)
	docker push \
	  $(DOCKER_HUB_USER)/check_mk-build-base:$(DEB_RELEASE)-$(ARCH)

PHONY: gcc
gcc: base
	docker build . \
	  -t check_mk-build-gcc:$(DEB_RELEASE)-$(GCC_VERSION)-$(ARCH) \
	  -f Dockerfile.gcc \
	  --build-arg DEB_RELEASE=$(DEB_RELEASE) \
	  --build-arg ARCH=$(ARCH) \
	  --build-arg GCC_VERSION=$(GCC_VERSION) \
	  --build-arg PARALLEL_BUILD=$(PARALLEL_BUILD)

PHONY: push_gcc
push_gcc: gcc
	docker tag \
	  check_mk-build-gcc:$(DEB_RELEASE)-$(GCC_VERSION)-$(ARCH) \
	  $(DOCKER_HUB_USER)/check_mk-build-gcc:$(DEB_RELEASE)-$(GCC_VERSION)-$(ARCH)
	docker push \
	  $(DOCKER_HUB_USER)/check_mk-build-gcc:$(DEB_RELEASE)-$(GCC_VERSION)-$(ARCH)

PHONY: cmk_deb
cmk_deb: gcc
	docker build . \
	  -t check_mk-build-deb:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH) \
	  -f Dockerfile.cmk_deb \
	  --build-arg DEB_RELEASE=$(DEB_RELEASE) \
	  --build-arg ARCH=$(ARCH) \
	  --build-arg GCC_VERSION=$(GCC_VERSION) \
	  --build-arg CMK_VERSION=$(CMK_VERSION)

PHONY: push_cmk_deb
push_cmk_deb: cmk_deb
	docker tag \
	  check_mk-build-deb:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH) \
	  $(DOCKER_HUB_USER)/check_mk-build-deb:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)
	docker push \
	  $(DOCKER_HUB_USER)/check_mk-build-deb:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)

check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/all.tar.gz:
	mkdir -p check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)
	docker run --rm check_mk-build-deb:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH) \
	  sh -c 'tar cvf - check-mk-raw-$(CMK_VERSION)*' \
        | tee check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/all.tar \
        | tar xvf - -C check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/
	gzip -vf check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/all.tar

PHONY: cmk_docker_image
cmk_docker_image: cmk_deb
	# extract the docker tar into a separate directory
	rm -rf cmk_docker
	mkdir cmk_docker
	tar -xvz \
	  -C cmk_docker \
	  --strip-components=1 \
	  -f check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/check-mk-raw-$(CMK_VERSION)-docker.tar.gz \
	  docker/
	# extract the variables to file
	echo 'all:\n\techo $$(OS_PACKAGES) > needed-packages' | make -C cmk_docker -f DEBIAN_9.mk -f -
	# link the package here
	ln -f check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/check-mk-*.deb cmk_docker
	# strip out dpkg-sig
	sed -i "/dpkg-sig/d" cmk_docker/Dockerfile
	# and build docker image
	docker build cmk_docker \
	  -t check_mk:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH) \
	  --build-arg DEB_RELEASE=$(DEB_RELEASE) \
	  --build-arg ARCH=$(ARCH) \
	  --build-arg GCC_VERSION=$(GCC_VERSION) \
	  --build-arg CMK_VERSION=$(CMK_VERSION) \
	  --build-arg CMK_EDITION=raw
	# remove directory
	rm -rf cmk_docker

PHONY: push_cmk_img
push_cmk_img: cmk_docker_image
	docker tag \
	  check_mk:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH) \
	  $(DOCKER_HUB_USER)/check_mk:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)
	docker push \
	  $(DOCKER_HUB_USER)/check_mk:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)
