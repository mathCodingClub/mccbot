<?php


parse_str(implode('&', array_slice($argv, 1)), $_GET);


require_once '/home/stenvala/Dropbox/Antti_htdocs/mccRest/models/tekstari/tekstari.php';

$response = "";

try {
      $t = new tekstari($_GET["page"]);
      $response = $t->getPage(tekstari::GET_PLAIN);
    } catch (Exception $e) {
      $response = $e->getCode();
    }

echo $response;

?>
