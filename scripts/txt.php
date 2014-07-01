<?php


parse_str(implode('&', array_slice($argv, 1)), $_GET);


require_once '/var/repos/tekstari/tekstari.php';

$response = "";

try {
      $t = new tekstari($_GET["page"]);
      $response = $t->getPage(tekstari::GET_PLAIN);
    } catch (Exception $e) {
      $response = $e->getCode();
    }

echo $response;

?>
