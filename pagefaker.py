# generate fake pageview data
import json
from datetime import datetime, timedelta
from typing import NamedTuple
from uuid import uuid4
import csv
from io import StringIO

from numpy import random


random.seed(10)

pages = '/home', '/about', '/listings', '/listing/a', '/listing/b', '/listing/b'


class ArgsToCsv:
    # from Stackoverflow... lost the link so can't give credit :(
    def __init__(self, seperator=","):
        self.seperator = seperator
        self.buffer = StringIO()
        self.writer = csv.writer(self.buffer)

    def stringify(self, *args):
        self.writer.writerow(args)
        value = self.buffer.getvalue().strip("\r\n")
        self.buffer.seek(0)
        self.buffer.truncate(0)
        return value

class User:
    def __init__(self):
        self.uuid = uuid4().hex
        self.session_length = int(random.exponential(10))
        self.mean_page_duration = 15  # random.exponential(15).. seconds
        self.age = 0  # minutes

csv_formatter = ArgsToCsv()
step = timedelta(minutes=1)

starttime = datetime(2020,1,1)
now = starttime + step

users = {user.uuid:user for user in [User(), User(), User()]}
returners = {}

# initialization
for user in users:
    users[user].age = random.exponential(5)

end = now + timedelta(days=365)
while now < end:
    to_delete = []

    # extant users
    for uuid in users:
        user = users[uuid]
        user.age += 1

        
        # exit
        if user.age > user.session_length:
            to_delete.append(user)

        # activity
        pageviews = random.choice([0, 1], p=[.80, .20])
        for pageview in range(pageviews):
            event = csv_formatter.stringify(
                uuid,
                now,
                'pageview',
                random.choice(pages)
            )
            print(event)

    for user in to_delete:
        return_in = random.exponential(1000)
        returners[now + timedelta(minutes=return_in)] = user
        del users[user.uuid]

    to_delete = []

    # reintroduce some old users
    if returners.get(now):
        for user in returners[now]:
            user.age = 0
            user.session_length = int(random.exponential(10))
            users[user.uuid] = user

        del returners[now]
    
    # add some new users
    num_new_users = random.poisson(1.5)
    new_users = [User() for _ in range(num_new_users)]
    for user in new_users:
        users[user.uuid] = user

    now += step

