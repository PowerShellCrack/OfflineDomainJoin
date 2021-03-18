# Change log for DomainJoin.ps1

## 1.0.2 - Mar 18 2021

- added TS variable check; allows simplified deployment with no variables
- fixed OSDisk variable if empty; uses first available letter
- set transaction loging to debug only; logs can have sensitive dat in it such as passwords. 

## 1.0.1 - Mar 17 2021

- Successfully got Windows domain to work; user account must be 20 character or less
- Added additional logging to domain join actions; provides verbose errors for troubleshooting
- Renamed JoinDomain.ps1 to DomainJoin.ps1; conflicted with JoinDomain transaction log for debugging

## 1.0.0 - Mar 16 2021

- missing global log path; added variable after function load
- missing TSenv function; detects if script is running in task sequence
- Added ODJ function; uses either blob or file
- Added Unattend function; updated unattend xml and adds required elements

## 1.0.0b Mar 15 2021

- Initial; added computer join function