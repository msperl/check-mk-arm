BASE_IMAGE=debian:stretch
CMK_VERSION=1.5.0p7
GCC_VERSION=7.3.0
DOCKER_HUB_USER=msperl
DEB_RELEASE=stretch
ARCH=arm
PARALLEL_BUILD=$(shell grep -c "^processor" /proc/cpuinfo)

all: base gcc cmk_deb check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/all.tar.gz
#push: push_base push_gcc

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
	docker push $(DOCKER_HUB_USER)/check_mk-build-base:$(DEB_RELEASE)-$(ARCH)

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
	docker push $(DOCKER_HUB_USER)/check_mk-build-gcc:$(GCC_VERSION)-$(ARCH)

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

check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/all.tar.gz: cmk_deb
	mkdir -p check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)
	docker run --rm check_mk-build-deb:$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH) \
	  sh -c 'tar cvf - check-mk-raw-$(CMK_VERSION)*' \
        | tee check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/all.tar \
        | tar xvf - -C check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/
	gzip -v check-mk-raw/$(CMK_VERSION)-$(GCC_VERSION)-$(ARCH)/all.tar