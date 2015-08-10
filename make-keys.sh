#!/bin/sh

# http://stackoverflow.com/questions/10175812/how-to-create-a-self-signed-certificate-with-openssl

openssl req -nodes -x509 -newkey rsa:2048 -keyout $HOME/new-key.pem -out $HOME/new-cert.pem -days 3650

