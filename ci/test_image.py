#!/usr/bin/env python

import requests
import urllib3

IMAGE_ID = 1
IMAGE_NAME = 'opengraph-repo-image.jpg'
IMAGE_OWNER = 'root'
USERNAME = 'root'
PASSWORD = 'omero'


def test_image():
    # Disable SSL warnings
    urllib3.disable_warnings()
    session = requests.Session()
    r = session.get('https://localhost', verify=False)
    r.raise_for_status()

    r = session.post('https://localhost/webclient/login/', data={
        'username': USERNAME,
        'password': PASSWORD,
        'csrfmiddlewaretoken': session.cookies['csrftoken'],
        'server': 1,
        'noredirect': 1,
    })
    r.raise_for_status()
    assert r.text == 'OK'

    r = session.get('https://localhost/api/v0/m/images/{}'.format(IMAGE_ID))
    r.raise_for_status()
    im = r.json()

    assert im['data']['Name'] == IMAGE_NAME
    assert im['data']['@id'] == IMAGE_ID
    assert im['data']['omero:details']['owner']['UserName'] == IMAGE_OWNER
