export JEKYLL_VERSION=3.8
docker run --rm \
  --volume="$PWD:/srv/jekyll" \
  -p 8888:4000 \
  -it jekyll/jekyll:$JEKYLL_VERSION \
  bash
