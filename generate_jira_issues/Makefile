
all: test create-issues

test: docker-build
	mkdir -p out.d
	cdir="$$(basename "$$(pwd)")" ; \
	docker run --rm -it \
        -v "$$(pwd)/..:/app" \
        -w "/app/$$cdir" \
        python:3.11-alpine3.16 \
            python3 ../csv_row_template_output.py changes.csv jira_template.tmpl out.d

create-issues:
	set -eu ; \
    for i in out.d/*.out ; do \
        docker run --rm -it \
            -e HOME=/root \
            -v "$$HOME/.jira.d:/root/.jira.d:ro" \
            -v "$$(pwd):$$(pwd):ro" \
            -w "$$(pwd)" \
            go-jira:latest \
                jira create -p "PROJECTKEY" --file "$$i" --noedit ; \
    done

docker-build:
	docker build -t go-jira:latest .
