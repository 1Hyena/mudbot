<?php

header('Content-Type:text/plain');

require('./auth.php');

if ($_SERVER['REQUEST_METHOD'] != 'POST') {
    header('Allow:POST');
    http_response_code(405);
    print "METHOD NOT ALLOWED";
    exit;
}

$size = (int) $_SERVER['CONTENT_LENGTH'];
if ($size === 0) {
    http_response_code(400);
    print "EMPTY POST BODY";
    exit;
}

$utc_time="".(floor(time()/60));

$postauth = getallheaders()['X-Auth'];
$postdata = file_get_contents("php://input");
$posthash = hash("sha256", $postdata.AUTH_TOKEN.$utc_time, false);

if (strlen($posthash) !== 64) {
    http_response_code(500);
    print "INTERNAL ERROR (".__LINE__.")";
    exit;
}

if ($posthash === $postauth) {
    $postdata = str_replace("<!--<title></title>-->", '<title></title>', $postdata);
    $postdata = str_replace("<title></title>", '<title>StoCam</title><META HTTP-EQUIV="refresh" CONTENT="10">', $postdata);

    $fp = fopen("index.html", "w") or die("Unable to open file!");
    fwrite($fp, $postdata);
    fclose($fp);
}
else {
    http_response_code(401);
    print "BAD X-Auth HEADER";
    exit;
}

http_response_code(201);
print $posthash;

