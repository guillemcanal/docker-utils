# Docker Utils

Make Docker sucks less on your development environment.  
You just need the [Docker toolbox](https://www.docker.com/toolbox) installed on your computer

## OMG Features!

So what can it do for you ?

### If you are on a Mac

- Update you routing tables in order to access your containers with ease
- Mount a NFS share between your Mac and your Docker machine without killing yourself
- Use a DNS server running in a container to access your stuff using a domain name

#### Installation

You can put the `docker-utils.sh` script anywhere on your mac 
(for example in your `~/bin` directory, which I recommend personally), 
but if you are lazy, feel free to copy/paste those lines in your terminal.

```
sudo curl -o /usr/local/bin/docker-utils https://raw.githubusercontent.com/guillemcanal/docker-utils/master/docker-utils.sh && \
sudo chmod +x /usr/local/bin/docker-utils
```

### If you are on Linux

Coming Soon.

### If you are on Windows

Coming Soon. (Boy! This one is tricky)

## Usage

`docker-utils`: display available commands and descriptions

```shell
Usage: docker-utils COMMAND DOCKER_MACHINE_NAME

Commands:
  create    Create a new machine with a NFS Share
  nfs       Create a NFS share on an existing docker machine
  start     Start a machine
  routing   Update the routing tables
  dns       Change the DNS domain used by your containers
```

### Tips and tricks 

So, my docker machine is named `default`  
Let say I have configured my DNS server with the following domain: `dev`  
If I need to create a container running nginx and access it with `omg.nginx.dev`

Here is what I need to do:

```
$ eval $(docker-machine env default)
$ docker run -d --name omg_nginx --hostname omg.nginx.dev nginx
```

`curl omg.nginx.dev -I`

```http
HTTP/1.1 200 OK
Server: nginx/1.9.4
Date: Sat, 29 Aug 2015 12:06:34 GMT
Content-Type: text/html
Content-Length: 612
Last-Modified: Tue, 18 Aug 2015 16:09:59 GMT
Connection: keep-alive
ETag: "55d358d7-264"
Accept-Ranges: bytes
```

At this point, you can put your hands in the air (like you just dont care)

## Credits

I mostly used the article [How Blackfire leverages Docker](http://blog.blackfire.io/how-we-use-docker.html) 
writted by [Tugdual Saunier](https://github.com/tucksaun) to put this script together. Many thanks to him.

Many thanks to [Ivo Verberk](https://github.com/iverberk) for his [docker-spy](https://github.com/iverberk/docker-spy) image.

## Notes

As of now, `docker-machine` does not provide a way to 
create a virtualbox docker-machine without a VirtualBox SharedFolder (which is silly).

In the upcoming version, you will be able to do a 
`docker-machine create -d virtualbox --virtualbox-no-share mybox`, but for now, 
this script need to stop you VM and remove the vboxfs share with `VBoxManage`.

Once you created or updated a docker machine with a NFS Share using `docker-utils`, 
you will **ALWAYS** need to start your VM using `docker-utils start [YOUR_DOCKER_MACHINE_NAME]`. 

Why (you may ask) ?

Because we need to:  
- Ensure that your NFS share is properly mounted, due to a [bug](https://github.com/docker/machine/issues/1755)
- Start the DNS container and update your DNS resolver if needed
- Update the routing tables

## Contribute

This script have some rough edges, if you think you can improve it, please do!
