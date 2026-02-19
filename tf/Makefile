PLAN_FILE=guardian.plan

HOST:=$(shell hostname)
PREFIX_HOST:=xxxxx
HOST_EXIST=$(findstring $(HOST),$(PREFIX_HOST))

ifneq ($(HOST_EXIST),)
	PREFIX=gk e -p pro-services-dev --
else
	PREFIX=
endif

main: plan

init:
	$(PREFIX) terraform init -upgrade

plan:
	$(PREFIX) terraform plan -out $(PLAN_FILE)

apply:
	$(PREFIX) terraform apply $(PLAN_FILE)

show:
	$(PREFIX) terraform show

clean:
	rm $(PLAN_FILE)

logs-api:
	aws logs tail --follow /api/logs

graph:
	$(PREFIX) terraform graph | dot -Tsvg > graph.svg

.PHONY: clean plan
