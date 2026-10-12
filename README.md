# CoffeeScheduler

An iPhone app that plans which bag of coffee to drink on which day, so each
one is brewed after it has rested and before it goes stale. Bags and brews
are imported from a [BeanConqueror](https://beanconqueror.com) export.

It shows the schedule as a month calendar or a list, the queue of bags, and
each bag's detail; it can freeze and thaw bags, reorder the queue, mark skip
days, and set rest days by roaster. There is a home screen widget, and Siri
can say what today's or tomorrow's coffee is.

The app is in [`ios/`](ios/README.md): a SwiftUI app built with
[xtool](https://github.com/xtool-org/xtool), so it builds and installs from
Linux or Windows (WSL) with no Mac. See [`ios/README.md`](ios/README.md) for
setup, tests and how the data is stored.

This repository used to hold a Next.js web app as well, which the iOS app
replaced. It is in the git history before the commit that removed it.
