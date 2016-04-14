# Socket Component

[![Build Status](https://secure.travis-ci.org/reactphp/socket.png?branch=master)](http://travis-ci.org/reactphp/socket)

Library for building an evented socket server.

The socket component provides a more usable interface for a socket-layer
server or client based on the [`EventLoop`](https://github.com/reactphp/event-loop)
and [`Stream`](https://github.com/reactphp/stream) components.

**Table of Contents**

* [Quickstart example](#quickstart-example)
* [Usage](#usage)
  * [Server](#server)
  * [Connection](#connection)
* [Install](#install)
* [License](#license)

## Quickstart example

Here is a server that closes the connection if you send it anything:

```php
$loop = React\EventLoop\Factory::create();

$socket = new React\Socket\Server($loop);
$socket->on('connection', function ($conn) {
    $conn->write("Hello there!\n");
    $conn->write("Welcome to this amazing server!\n");
    $conn->write("Here's a tip: don't say anything.\n");

    $conn->on('data', function ($data) use ($conn) {
        $conn->close();
    });
});
$socket->listen(1337);

$loop->run();
```

You can change the host the socket is listening on through a second parameter 
provided to the listen method:

```php
$socket->listen(1337, '192.168.0.1');
```

Here's a client that outputs the output of said server and then attempts to
send it a string.
For anything more complex, consider using the
[`SocketClient`](https://github.com/reactphp/socket-client) component instead.

```php
$loop = React\EventLoop\Factory::create();

$client = stream_socket_client('tcp://127.0.0.1:1337');
$conn = new React\Stream\Stream($client, $loop);
$conn->pipe(new React\Stream\Stream(STDOUT, $loop));
$conn->write("Hello World!\n");

$loop->run();
```

## Usage

### Server

The server can listen on a port and will emit a `connection` event whenever a
client connects.

### Connection

The `Connection` is a readable and writable [`Stream`](https://github.com/reactphp/stream).
The incoming connection represents the server-side end of the connection.

It MUST NOT be used to represent an outgoing connection in a client-side context.
If you want to establish an outgoing connection,
use the [`SocketClient`](https://github.com/reactphp/socket-client) component instead.

## Install

The recommended way to install this library is [through Composer](http://getcomposer.org).
[New to Composer?](http://getcomposer.org/doc/00-intro.md)

This will install the latest supported version:

```bash
$ composer require react/socket:~0.4.0
```

If you care a lot about BC, you may also want to look into supporting legacy versions:

```bash
$ composer require "react/socket:~0.4.0|~0.3.0"
```

More details and upgrade guides can be found in the [CHANGELOG](CHANGELOG.md).

## License

MIT, see [LICENSE file](LICENSE).
