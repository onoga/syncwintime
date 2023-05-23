@echo off
pip install virtualenv
virtualenv .env
call .env\scripts\activate
pip install pyinstaller 
pyinstaller --onefile syncwintime.py
