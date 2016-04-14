<?php

namespace React\Tests\Stream;

use React\Stream\Stream;
use React\EventLoop as rel;

class StreamIntegrationTest extends TestCase
{
    public function loopProvider()
    {
        return array(
            array(function() { return true; }, function() { return new rel\StreamSelectLoop; }),
            array(function() { return function_exists('event_base_new'); }, function() { return new rel\LibEventLoop; }),
            array(function() { return class_exists('libev\EventLoop'); }, function() { return new rel\LibEvLoop; }),
            array(function() { return class_exists('EventBase'); }, function() { return new rel\ExtEventLoop; })
        );
    }

    /**
     * @dataProvider loopProvider
     */
    public function testBufferReadsLargeChunks($condition, $loopFactory)
    {
        if (true !== $condition()) {
            return $this->markTestSkipped('Loop implementation not available');
        }

        $loop = $loopFactory();

        list($sockA, $sockB) = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, 0);

        $streamA = new Stream($sockA, $loop);
        $streamB = new Stream($sockB, $loop);

        $bufferSize = 4096;
        $streamA->bufferSize = $bufferSize;
        $streamB->bufferSize = $bufferSize;

        $testString = str_repeat("*", $streamA->bufferSize + 1);

        $buffer = "";
        $streamB->on('data', function ($data, $streamB) use (&$buffer, &$testString) {
            $buffer .= $data;
        });

        $streamA->write($testString);

        $loop->tick();
        $loop->tick();
        $loop->tick();

        $streamA->close();
        $streamB->close();

        $this->assertEquals($testString, $buffer);
    }
}
