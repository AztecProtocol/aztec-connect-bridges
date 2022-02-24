FROM node:14-alpine AS builder
RUN apk update && apk add --no-cache build-base git python3 curl bash tar

WORKDIR /usr/src/
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY . .

SHELL ["/bin/bash", "-c"]
RUN yarn config set script-shell /bin/bash
RUN curl -L https://foundry.paradigm.xyz | bash || true
RUN export PATH=/root/.foundry/bin:$PATH && yarn setup:foundry
RUN export PATH=/root/.forge/bin:$PATH yarn compile:typechain
CMD ["yarn test"]


RUN yarn install --frozen-lockfile && yarn test --runInBand && yarn build && rm -rf node_modules && yarn cache clean

FROM node:14-alpine
COPY --from=0 /usr/src/client-dest /usr/src/client-dest
