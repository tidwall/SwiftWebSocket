<?php

namespace React\Tests\EventLoop;

use React\EventLoop\LoopInterface;
use React\EventLoop\StreamSelectLoop;

class StreamSelectLoopTest extends AbstractLoopTest
{
    protected function tearDown()
    {
        parent::tearDown();
        if (strncmp($this->getName(false), 'testSignal', 10) === 0 && extension_loaded('pcntl')) {
            $this->resetSignalHandlers();
        }
    }

    public function createLoop()
    {
        return new StreamSelectLoop();
    }

    public function testStreamSelectTimeoutEmulation()
    {
        $this->loop->addTimer(
            0.05,
            $this->expectCallableOnce()
        );

        $start = microtime(true);

        $this->loop->run();

        $end = microtime(true);
        $interval = $end - $start;

        $this->assertGreaterThan(0.04, $interval);
    }

    public function testStopShouldPreventRunFromBlocking($timeLimit = 0.005)
    {
        if (defined('HHVM_VERSION')) {
            // HHVM is a bit slow, so give it more time
            parent::testStopShouldPreventRunFromBlocking(0.5);
        } else {
            parent::testStopShouldPreventRunFromBlocking($timeLimit);
        }
    }


    public function signalProvider()
    {
        return [
            ['SIGUSR1', SIGUSR1],
            ['SIGHUP', SIGHUP],
            ['SIGTERM', SIGTERM],
        ];
    }

    private $_signalHandled = false;

    /**
     * Test signal interrupt when no stream is attached to the loop
     * @dataProvider signalProvider
     */
    public function testSignalInterruptNoStream($sigName, $signal)
    {
        if (!extension_loaded('pcntl')) {
            $this->markTestSkipped('"pcntl" extension is required to run this test.');
        }

        // dispatch signal handler once before signal is sent and once after
        $this->loop->addTimer(0.01, function() { pcntl_signal_dispatch(); });
        $this->loop->addTimer(0.03, function() { pcntl_signal_dispatch(); });
        if (defined('HHVM_VERSION')) {
            // hhvm startup is slow so we need to add another handler much later
            $this->loop->addTimer(0.5, function() { pcntl_signal_dispatch(); });
        }

        $this->setUpSignalHandler($signal);

        // spawn external process to send signal to current process id
        $this->forkSendSignal($signal);
        $this->loop->run();
        $this->assertTrue($this->_signalHandled);
    }

    /**
     * Test signal interrupt when a stream is attached to the loop
     * @dataProvider signalProvider
     */
    public function testSignalInterruptWithStream($sigName, $signal)
    {
        if (!extension_loaded('pcntl')) {
            $this->markTestSkipped('"pcntl" extension is required to run this test.');
        }

        // dispatch signal handler every 10ms
        $this->loop->addPeriodicTimer(0.01, function() { pcntl_signal_dispatch(); });

        // add stream to the loop
        list($writeStream, $readStream) = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, STREAM_IPPROTO_IP);
        $this->loop->addReadStream($readStream, function($stream, $loop) {
            /** @var $loop LoopInterface */
            $read = fgets($stream);
            if ($read === "end loop\n") {
                $loop->stop();
            }
        });
        $this->loop->addTimer(0.05, function() use ($writeStream) {
            fwrite($writeStream, "end loop\n");
        });

        $this->setUpSignalHandler($signal);

        // spawn external process to send signal to current process id
        $this->forkSendSignal($signal);

        $this->loop->run();

        $this->assertTrue($this->_signalHandled);
    }

    /**
     * add signal handler for signal
     */
    protected function setUpSignalHandler($signal)
    {
        $this->_signalHandled = false;
        $this->assertTrue(pcntl_signal($signal, function() { $this->_signalHandled = true; }));
    }

    /**
     * reset all signal handlers to default
     */
    protected function resetSignalHandlers()
    {
        foreach($this->signalProvider() as $signal) {
            pcntl_signal($signal[1], SIG_DFL);
        }
    }

    /**
     * fork child process to send signal to current process id
     */
    protected function forkSendSignal($signal)
    {
        $currentPid = posix_getpid();
        $childPid = pcntl_fork();
        if ($childPid == -1) {
            $this->fail("Failed to fork child process!");
        } else if ($childPid === 0) {
            // this is executed in the child process
            usleep(20000);
            posix_kill($currentPid, $signal);
            die();
        }
    }
}
