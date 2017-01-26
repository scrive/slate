import os

import tests
from make_drivers import generate_tests
from scrivepy import Language
from selenium import webdriver


###############################################################################
#                                   INFO                                      #
# This script lists and configures selenium tests.                            #
# It's not supposed to be run, but nosetests will auto-discover it            #
# Configuration is based on two things:                                       #
# * config.py file (if it does not exist, you will be notified,               #
#   including example values)                                                 #
# * environment variables:                                                    #
# ** SELENIUM_REMOTE_TESTS - 1 means run tests on sauce labs,                 #
#                            0 use local browsers (default)                   #
# ** SELENIUM_SINGLE_TEST - if defined, its value has to be a name            #
#                           of the only test that will be run                 #
###############################################################################
DC = webdriver.DesiredCapabilities

LOCAL_DEVICES = [{'driver': webdriver.Firefox,
                  'name': DC.FIREFOX['browserName']}]

REMOTE_DEVICES = [{'browserName': "chrome",
                   'chromeOptions': {'args': ['--disable-extensions']},
                   'platform': 'Windows 8.1',
                   'window-size': (1040, 784),
                   'screenshot-prefix': 'desktop',
                   'version': 'beta'},
                  {'browserName': "chrome",
                   'chromeOptions': {'args': ['--disable-extensions']},
                   'window-size': (619, 706),
                   'screenshot-prefix': 'mobile',
                   'platform': 'Windows 8.1',
                   'version': 'beta'}]


dir_path = os.path.dirname(os.path.abspath(__file__))
artifact_dir = os.path.join(dir_path, 'artifacts')


# this function is autocalled by nosetests, so it's like main()
def make_tests():
    for lang in Language:
        for x in generate_tests(tests, artifact_dir,
                                LOCAL_DEVICES, REMOTE_DEVICES,
                                lang=lang.value, screenshots_enabled=True):
            yield x
