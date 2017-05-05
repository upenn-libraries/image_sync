## README for image_sync
This is a small script for migrating, naming, and tracking versions of JP2 images generated for work with SharedShelf.

It relies on Ruby 2.2.5 and rsync.  It can be run in Docker with docker-compose.

To build in Docker (from within the repo's root directory):
```bash
docker build . -t image_sync:latest
```

To run with docker-compose:
```bash
docker-compose run image_sync ruby image_sync.rb /fs/source $COLLECTION_NAMESPACE
```
