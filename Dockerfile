FROM jekyll/jekyll:pages
ADD . /srv/jekyll
EXPOSE 4000
ENTRYPOINT ["jekyll", "serve", "--host=0.0.0.0"]
