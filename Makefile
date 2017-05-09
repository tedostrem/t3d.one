.PHONY : build run

build :
	docker build -t site .

run :
	docker rm -f nginx-proxy || true
	docker run -d -p 80:80 -p 443:443 \
    --name nginx-proxy \
    -v `pwd`/certs:/etc/nginx/certs:ro \
    -v /etc/nginx/vhost.d \
    -v `pwd`/access.log:/var/log/nginx/access.log \
    -v /usr/share/nginx/html \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    jwilder/nginx-proxy
	docker rm -f letsencrypt || true
	docker run -d \
		--name letsencrypt \
		-v `pwd`/certs:/etc/nginx/certs:rw \
		--volumes-from nginx-proxy \
		-v /var/run/docker.sock:/var/run/docker.sock:ro \
		jrcs/letsencrypt-nginx-proxy-companion
	docker rm -f site || true
	docker run --name site --label=jekyll \
		-e LETSENCRYPT_HOST=t3d.one,www.t3d.one \
		-e LETSENCRYPT_EMAIL=ted.ostrem@gmail.com \
		-e VIRTUAL_HOST=t3d.one,www.t3d.one \
		-e VIRTUAL_PORT=4000 \
		-d \
		site
