# SplunkKOHelper
Powershell script to orchestrate identification and correction of reports and dashboards requring updates to support Splunk app for Windows v5 deployment.

Synopsis:
-----------------------------------

Employs Splunk REST API to find searches and views having legacy wineventlog sourcetype references.  User can select one or more knowledge objects to review.

![alt tag](https://github.com/dstaulcu/SplunkKOHelper/blob/master/screencaps/snap1.JPG)

Transformations are drafted automatically and differences are displayed in windiff application.  Note, if the transformation was not perfect, you can edit the right side file through windiff to fine tune changes.

![alt tag](https://github.com/dstaulcu/SplunkKOHelper/blob/master/screencaps/snap2.JPG)

If changes are accepted, new source is placed in clipbard.

![alt tag](https://github.com/dstaulcu/SplunkKOHelper/blob/master/screencaps/snap3.JPG)

The view or dashboard is then automatically opened for editing in a new browser window where changes can be pasted from clipboard and saved.  

![alt tag](https://github.com/dstaulcu/SplunkKOHelper/blob/master/screencaps/snap4.JPG)

Both searches and views are supported.

![alt tag](https://github.com/dstaulcu/SplunkKOHelper/blob/master/screencaps/snap5.JPG)

![alt tag](https://github.com/dstaulcu/SplunkKOHelper/blob/master/screencaps/snap6.JPG)

![alt tag](https://github.com/dstaulcu/SplunkKOHelper/blob/master/screencaps/snap7.JPG)

