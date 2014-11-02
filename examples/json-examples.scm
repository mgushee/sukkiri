(define json-examples '(
"{ \"%TYPE\": \"project\",
  \"%ID\": \"breed-mutant-seahorses\",
  \"%LABEL\": \"title\",
  \"title\": \"Breed Mutant Seahorses\",
  \"deadline\": \"2014-03-28T17:00:00\",
  \"contact\": \"%NREF%jane-morgan\",
  \"step\": [\"%NREF%build-tank\", \"%NREF%catch-seahorses\", \"%NREF%assign-to-tanks\"] }"
"{ \"%TYPE\": \"action\",
  \"%ID\": \"build-tank\",
  \"%LABEL\": \"content\",
  \"content\": \"Build tank for seahorses\",
  \"context\": [\"lab\"] }"
"{ \"%TYPE\": \"person\",
  \"%ID\": \"jane-morgan\",
  \"%LABEL\": \"given-name & surname\",
  \"given-name\": \"Jane\",
  \"surname\": \"Morgan\",
  \"email\": [\"%NREF%jane-morgan-work-email\"] }"
"{ \"%TYPE\": \"email-address\",
  \"%ID\": \"jane-morgan-work-email\",
  \"label\": \"Work\",
  \"address\": \"dr.jane.v.morgan@sea-creature-research.com\" }"
))