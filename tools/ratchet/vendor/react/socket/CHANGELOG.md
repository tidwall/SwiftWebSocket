# Changelog

## 0.4.3 (2016-03-01)

* Bug fix: Suppress errors on stream_socket_accept to prevent PHP from crashing
* Support for PHP7 and HHVM
* Support PHP 5.3 again

## 0.4.2 (2014-05-25)

* Verify stream is a valid resource in Connection

## 0.4.1 (2014-04-13)

* Bug fix: Check read buffer for data before shutdown signal and end emit (@ArtyDev)
* Bug fix: v0.3.4 changes merged for v0.4.1

## 0.3.4 (2014-03-30)

* Bug fix: Reset socket to non-blocking after shutting down (PHP bug)

## 0.4.0 (2014-02-02)

* BC break: Bump minimum PHP version to PHP 5.4, remove 5.3 specific hacks
* BC break: Update to React/Promise 2.0
* BC break: Update to Evenement 2.0
* Dependency: Autoloading and filesystem structure now PSR-4 instead of PSR-0
* Bump React dependencies to v0.4

## 0.3.3 (2013-07-08)

* Version bump

## 0.3.2 (2013-05-10)

* Version bump

## 0.3.1 (2013-04-21)

* Feature: Support binding to IPv6 addresses (@clue)

## 0.3.0 (2013-04-14)

* Bump React dependencies to v0.3

## 0.2.6 (2012-12-26)

* Version bump

## 0.2.3 (2012-11-14)

* Version bump

## 0.2.0 (2012-09-10)

* Bump React dependencies to v0.2

## 0.1.1 (2012-07-12)

* Version bump

## 0.1.0 (2012-07-11)

* First tagged release
