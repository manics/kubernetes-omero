#!/usr/bin/env python

import os
import requests
import urllib3

IMAGE_ID = 1
IMAGE_NAME = "opengraph-repo-image.jpg"
IMAGE_OWNER = "root"
SERVER = os.getenv("SERVER", "https://localhost")
USERNAME = "root"
PASSWORD = "omero"


def test_image():
    # Disable SSL warnings
    urllib3.disable_warnings()
    session = requests.Session()
    r = session.get(f"{SERVER}", verify=False)
    r.raise_for_status()

    r = session.post(
        f"{SERVER}/webclient/login/",
        data={
            "username": USERNAME,
            "password": PASSWORD,
            "csrfmiddlewaretoken": session.cookies["csrftoken"],
            "server": 1,
            "noredirect": 1,
        },
        verify=False,
    )
    r.raise_for_status()
    assert r.text == "OK"

    r = session.get(f"{SERVER}/api/v0/m/images/{IMAGE_ID}", verify=False)
    r.raise_for_status()
    im = r.json()

    assert im["data"]["Name"] == IMAGE_NAME
    assert im["data"]["@id"] == IMAGE_ID
    assert im["data"]["omero:details"]["owner"]["UserName"] == IMAGE_OWNER
