<?php
use Ratchet\MessageComponentInterface;
use Ratchet\ConnectionInterface;

    // Make sure composer dependencies have been installed
    require __DIR__ . '/vendor/autoload.php';

class EchoServer implements MessageComponentInterface {

    public function onOpen(ConnectionInterface $conn) {
        echo "client opened\n";
    }

    public function onMessage(ConnectionInterface $from, $msg) {
        $from->send($msg);
        $from->count++;
        if ($from->count == 5){
            $from->close(4012);
        }
    }

    public function onClose(ConnectionInterface $conn) {
    }

    public function onError(ConnectionInterface $conn, \Exception $e) {
        $conn->close();
    }
}

$app = new Ratchet\App('localhost', 6790);
$app->route('/echo', new EchoServer, array('*'));
echo "Connect to ws://localhost:6790/echo\n";
$app->run();