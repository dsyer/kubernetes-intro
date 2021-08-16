Run Github actions locally using `act`. Build the base image (from the root directory):

```
$ docker build .github/act -t dsyer/act-latest
```

then use it to run the actions:

```
$ act -P ubuntu-latest=dsyer/act-latest -s GITHUB_TOKEN=$GITHUB_TOKEN
```