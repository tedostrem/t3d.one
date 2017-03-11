FROM jekyll/jekyll:pages
ADD . /srv/jekyll
ENTRYPOINT ["jekyll", "serve", "--host=0.0.0.0"]
