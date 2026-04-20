goal: rsa ec

rsa:
	openssl genrsa -out private.pem 2048
	openssl rsa -in private.pem -pubout -out public.pem

ec:
	openssl ecparam -genkey -name prime256v1 -noout -out ec-private.pem
	openssl ec -in ec-private.pem -pubout -out ec-public.pem