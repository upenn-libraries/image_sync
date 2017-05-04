FROM ruby:2.2.5-slim

MAINTAINER katherly@upenn.edu

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
  build-essential \
  rsync

ENV IM_VOLATILE /volatile

ENV IM_CANONICAL /canonical

RUN mkdir /fs

RUN mkdir /fs/source

RUN mkdir /fs/destination

RUN mkdir /fs/volatile

RUN mkdir /fs/canonical

RUN mkdir /usr/src/app

ADD . /usr/src/app/

WORKDIR /usr/src/app/

CMD ["ruby", "/usr/src/app/image_sync.rb"]