FROM kong:3.3.0-ubuntu
USER root

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=true

RUN mkdir -p /home/kong

RUN apt-get update \
&& apt-get -y install sudo vim python3-pip \
&& apt-get clean \
&& pip3 install --upgrade pip setuptools poetry==1.4.1

COPY ./pyproject.toml ./poetry.lock /home/kong/
RUN cd /home/kong && poetry install --no-dev

COPY ./src/py /home/kong/plugins
COPY ./src/bin /home/kong/bin
RUN chmod -R 775 /home/kong/plugins /home/kong/bin

RUN chown -R kong:kong /home/kong

USER kong
ENTRYPOINT ["/docker-entrypoint.sh"]
EXPOSE 8000
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=10s --timeout=10s --retries=10 CMD kong health
CMD ["kong", "docker-start"]
