.PHONY : build run

build :
	docker build -t site .

run :
	docker rm -f site || true
	docker run --name site --label=jekyll \
		-d -p 80:4000 site
