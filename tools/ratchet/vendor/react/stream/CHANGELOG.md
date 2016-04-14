# Changelog

## 0.4.3 (2015-10-07)

* Bug fix: Read buffer to 0 fixes error with libevent and large quantity of I/O (@mbonneau)
* Bug fix: No double-write during drain call (@arnaud-lb)
* Bug fix: Support HHVM (@clue)
* Adjust compatibility to 5.3 (@clue)

## 0.4.2 (2014-09-09)

* Added DuplexStreamInterface
* Stream sets stream resources to non-blocking
* Fixed potential race condition in pipe

## 0.4.1 (2014-04-13)

* Bug fix: v0.3.4 changes merged for v0.4.1

## 0.3.4 (2014-03-30)

* Bug fix: [Stream] Fixed 100% CPU spike from non-empty write buffer on closed stream

## 0.4.0 (2014-02-02)

* BC break: Bump minimum PHP version to PHP 5.4, remove 5.3 specific hacks
* BC break: Update to Evenement 2.0
* Dependency: Autoloading and filesystem structure now PSR-4 instead of PSR-0

## 0.3.3 (2013-07-08)

* Bug fix: [Stream] Correctly detect closed connections

## 0.3.2 (2013-05-10)

* Bug fix: [Stream] Make sure CompositeStream is closed properly

## 0.3.1 (2013-04-21)

* Bug fix: [Stream] Allow any `ReadableStreamInterface` on `BufferedSink::createPromise()`

## 0.3.0 (2013-04-14)

* Feature: [Stream] Factory method for BufferedSink

## 0.2.6 (2012-12-26)

* Version bump

## 0.2.5 (2012-11-26)

* Feature: Make BufferedSink trigger progress events on the promise (@jsor)

## 0.2.4 (2012-11-18)

* Feature: Added ThroughStream, CompositeStream, ReadableStream and WritableStream
* Feature: Added BufferedSink

## 0.2.3 (2012-11-14)

* Version bump

## 0.2.2 (2012-10-28)

* Version bump

## 0.2.1 (2012-10-14)

* Bug fix: Check for EOF in `Buffer::write()`

## 0.2.0 (2012-09-10)

* Version bump

## 0.1.1 (2012-07-12)

* Bug fix: Testing and functional against PHP >= 5.3.3 and <= 5.3.8

## 0.1.0 (2012-07-11)

* First tagged release
