#!/bin/sh
# /*******************************************************************************
#  * (c) Copyright IBM Corporation 2022.
#  *
#  * Licensed under the Apache License, Version 2.0 (the "License");
#  * you may not use this file except in compliance with the License.
#  * You may obtain a copy of the License at
#  *
#  *    http://www.apache.org/licenses/LICENSE-2.0
#  *
#  * Unless required by applicable law or agreed to in writing, software
#  * distributed under the License is distributed on an "AS IS" BASIS,
#  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  * See the License for the specific language governing permissions and
#  * limitations under the License.
#  *******************************************************************************/

# usage: guesslink.sh
LINK="$(ip link show | awk '/^[0-9].*state UP/ && !/lo:/ {gsub(/:/, "", $2); print $2; exit 0;}')"
if [ "${LINK}" != "" ]; then
  echo "${LINK}"
else
  echo "Could not guess link in output: $(ip link show)" >>/dev/stderr
fi
