import datetime
import hashlib
import json
import os
import pathlib
import re
import xml.etree.ElementTree as ET
from abc import ABC
from collections import Counter
from typing import List, Optional, Set, Union

import pandas as pd
from reports.mutants import JudyMutant, JumbleMutant, MajorMutant, Mutant, PitMutant

ERR_EXTRACT = (
    "An exception was raised when extracting the content of {fp}.\n"
    "Maybe this is the wrong file for this Report?"
)
ERR_EXTRACT_MULT = (
    "An exception was raised when extracting the contents of {fps}.\n"
    "Maybe these are the wrong files for this Report?"
)


class ReportError(Exception):
    """Base report error"""


class MultipleClassUnderMutationError(Exception):
    """Only a class under mutation at time can be analyzed
    because of Jumble - working on a single class at time"""


class MissingMutantCountException(ReportError):
    """Exception when a mutant list count is missing,
    This can happen if it's impossible to extract
    information about that particular kind of
     mutants from a report"""


class OverlappingMutantsError(ReportError):
    """Exception raised when there are two
    or more mutants in a sequence that shares the same
    hash key; because collisions are unlikely with SHA256,
    this means that the Mutant interface needs a counter"""


class JudyReportError(ReportError):
    """Judy specialized report error"""


class EmptyJudyReportError(JudyReportError):
    """Error raised when a report is empty"""


class MissingClassFromJudyReportError(JudyReportError):
    """Exception when the desired class is
    missing from a report"""


class MultipleClassFromJudyReportError(JudyReportError):
    """Error when the desired class is found
    multiple times in a report"""


class JumbleReportError(ReportError):
    """Jumble specialized report error"""


class MajorReportError(ReportError):
    """Major specialized report error"""


class PitReportError(ReportError):
    """Pit specialized report error"""


class WrongTagInPitReportError(PitReportError):
    """Error raised when a non-mutation element is
    encountered parsing an XML Pit report"""


class Report(ABC):
    class_under_mutation: str

    def __init__(self):
        self._created_at = datetime.datetime.now()

        self.killed_mutants: Optional[List[Mutant]] = None
        self.live_mutants: Optional[List[Mutant]] = None
        self._killed_mutants_count: Optional[int] = None
        self._live_mutants_count: Optional[int] = None

    def hash_string(self) -> str:
        """Hash algorithm hex digest
        converted to string"""
        raise NotImplementedError

    def __hash__(self) -> int:
        """hash string value (hex)
        converted to int, to match
        Python __hash__ return value"""
        return int(self.hash_string(), base=16)

    def summary(self, print_mutants: bool = False) -> str:
        mutscore = self.killed_mutants_count / self.total_mutants_count
        buffer = [
            f"{self.__class__.__name__} Summary [Hash: {self.hash_string()}]",
            f"Report created at:    {self._created_at}",
            f"Mutated class:        {self.class_under_mutation}",
            f"Total mutants count:  {self.total_mutants_count}",
            f"Killed mutants count: {self.killed_mutants_count}",
            f"Live mutants count:   {self.live_mutants_count}",
            f"Mutation score:       {mutscore}",
        ]

        for mutants_arr, mutants_str in zip(
            [self.killed_mutants, self.live_mutants], ["Killed", "Live"]
        ):
            if mutants_arr:
                buffer.append(f"{mutants_str} mutants report:")
                if print_mutants:
                    buffer.append("\n".join(str(m) for m in mutants_arr))
                else:
                    buffer.append("< SNIP >")
            else:
                buffer.append(f"Cannot report {mutants_str} mutants")

        return "\n".join(buffer)

    @staticmethod
    def find_overlapping_mutants(mutants: List[Mutant]) -> Set[Mutant]:
        """This brief algorithm finds the mutants that are duplicates,
        i.e. their hash value is equal."""
        counter = Counter([hash(mutant) for mutant in mutants])
        duplicates = [h for (h, c) in counter.items() if c > 1]
        return set([m for m in mutants if hash(m) in duplicates])

    def sanity_check(self):
        """Check for overlapping mutants"""
        if self.killed_mutants:
            set_killed = self.find_overlapping_mutants(self.killed_mutants)
            if set_killed:
                raise OverlappingMutantsError(set_killed)

        if self.live_mutants:
            set_live = self.find_overlapping_mutants(self.live_mutants)
            if set_live:
                raise OverlappingMutantsError(set_live)

        if not self.class_under_mutation:
            raise ReportError(
                "Cannot set class under mutation! Maybe input report was broken?"
            )

    @property
    def killed_mutants_count(self) -> int:
        if self.killed_mutants is not None:
            return len(self.killed_mutants)
        elif self._killed_mutants_count is not None:
            return self._killed_mutants_count
        else:
            raise MissingMutantCountException()

    @property
    def live_mutants_count(self) -> int:
        if self.live_mutants is not None:
            return len(self.live_mutants)
        elif self._live_mutants_count is not None:
            return self._live_mutants_count
        else:
            raise MissingMutantCountException()

    @property
    def total_mutants_count(self) -> int:
        return self.killed_mutants_count + self.live_mutants_count

    def __repr__(self):
        return (
            f"Report(class_under_mutation={self.class_under_mutation},"
            f" killed_count={self.killed_mutants_count},"
            f" live_count={self.live_mutants_count},"
            f" total_count={self.total_mutants_count})"
        )


class SingleFileReport(Report):
    def __init__(self, filepath: Union[str, os.PathLike]):
        super(SingleFileReport, self).__init__()

        self.filepath = pathlib.Path(filepath)
        content = open(self.filepath, "rb").read()
        self._hash_string = hashlib.md5(content).hexdigest()
        try:
            self.extract()
        except Exception:
            raise ReportError(ERR_EXTRACT.format(fp=self.filepath))

        self.sanity_check()

    def hash_string(self):
        return self._hash_string

    def extract(self, **kwargs):
        raise NotImplementedError

    def summary(self, print_mutants: bool = False) -> str:
        summary = super(SingleFileReport, self).summary(print_mutants=print_mutants)
        fp = str(self.filepath)
        return f"{summary}\nFilepath: {fp}"


class MultipleFilesReport(Report):
    def __init__(self, *filepaths: Union[str, os.PathLike]):
        super(MultipleFilesReport, self).__init__()

        self.filepaths = [pathlib.Path(fp) for fp in filepaths]
        content = b"\n".join(open(fp, "rb").read() for fp in self.filepaths)
        self._hash_string = hashlib.md5(content).hexdigest()
        try:
            self.extract()
        except Exception:
            raise ReportError(ERR_EXTRACT_MULT.format(fps=self.filepaths))

        self.sanity_check()

    def hash_string(self):
        return self._hash_string

    def extract(self, **kwargs):
        raise NotImplementedError

    def summary(self, print_mutants: bool = False) -> str:
        summary = super(MultipleFilesReport, self).summary(print_mutants=print_mutants)
        fps = [str(fp) for fp in self.filepaths]
        return f"{summary}\nFilepaths: {fps}"


class SingleJudyReport(SingleFileReport):
    def __init__(
        self,
        json_filepath: Union[str, os.PathLike],
        class_under_mutation: str,
    ):
        self.class_under_mutation = class_under_mutation
        self.json_fp = pathlib.Path(json_filepath)
        super(SingleJudyReport, self).__init__(json_filepath)

    def __repr__(self):
        return "SingleJudy" + super(SingleJudyReport, self).__repr__()

    def _extract_json(self):
        """Parse live mutants from json report"""
        judy_dict = json.loads(open(self.json_fp).read())

        classes = judy_dict["classes"]
        if not classes:
            raise EmptyJudyReportError(
                "No mutated class found! There were some errors in execution phase"
            )

        thedict = [
            adict for adict in classes if adict["name"] == self.class_under_mutation
        ]

        if len(thedict) == 0:
            raise MissingClassFromJudyReportError(
                f"{self.class_under_mutation} not found!"
            )
        elif len(thedict) > 1:
            raise MultipleClassFromJudyReportError(
                f"{self.class_under_mutation} found multiple times!"
            )
        else:
            thedict = thedict[0]

        JudyMutant.reset_counter()
        self._killed_mutants_count = thedict["mutantsKilledCount"]
        self.live_mutants = [
            JudyMutant.from_dict(mdict) for mdict in thedict["notKilledMutant"]
        ]

    def extract(self):
        self._extract_json()


class MultipleJudyReport(MultipleFilesReport):
    def __init__(
        self,
        json_filepath: Union[str, os.PathLike],
        log_filepath: Union[str, os.PathLike],
        class_under_mutation: str,
    ):
        self.class_under_mutation = class_under_mutation
        self.json_fp = pathlib.Path(json_filepath)
        self.log_fp = pathlib.Path(log_filepath)
        super(MultipleJudyReport, self).__init__(json_filepath, log_filepath)

    def __repr__(self):
        return "MultipleJudy" + super(MultipleJudyReport, self).__repr__()

    def _extract_json(self):
        """Parse live mutants from json report"""
        judy_dict = json.loads(open(self.json_fp).read())

        classes = judy_dict["classes"]
        if not classes:
            raise EmptyJudyReportError(
                "No mutated class found! There were some errors in execution phase"
            )

        thedict = [
            adict for adict in classes if adict["name"] == self.class_under_mutation
        ]

        if len(thedict) == 0:
            raise MissingClassFromJudyReportError(
                f"{self.class_under_mutation} not found!"
            )
        elif len(thedict) > 1:
            raise MultipleClassFromJudyReportError(
                f"{self.class_under_mutation} found multiple times!"
            )
        else:
            thedict = thedict[0]

        JudyMutant.reset_counter()
        self._killed_mutants_count = thedict["mutantsKilledCount"]
        self.live_mutants = [
            JudyMutant.from_dict(mdict) for mdict in thedict["notKilledMutant"]
        ]

    def _extract_log(self):
        """Extract killed mutants through log"""
        lines = open(self.log_fp).readlines()
        regexp = (
            r"DEBUG\s+pl\.edu\.pwr\.judy\.research\.fragility\.ResearchDataCollector"
            r"\s+-?\s*\s+[\w\.]+\s*(\d+)\s*(\d+)\s*(\w+)\s*\[?([^\]]+)\]?\s*([\w\.]+)"
        )
        pattern = re.compile(regexp)
        mutations = set()

        for line in lines:
            match = pattern.search(line)
            if not match:
                continue
            points = match.group(1)
            mutant_id = match.group(2)
            operator = match.group(3)
            line = match.group(4)
            # killed_test = match.group(5)

            # adding in a set will result in collision removal
            entry = (points, mutant_id, operator, line)
            mutations.add(entry)

        self.killed_mutants = [JudyMutant.from_tuple(t) for t in mutations]

    def extract(self):
        self._extract_json()
        self._extract_log()


class JumbleReport(SingleFileReport):
    def __repr__(self):
        return "Jumble" + super(JumbleReport, self).__repr__()

    def extract(self):
        content = open(self.filepath).read()

        class_pattern = re.compile(r"Mutating (.+)")
        self.class_under_mutation = class_pattern.search(content).group(1)

        fail_pattern = re.compile(r"M FAIL:\s*([a-zA-Z.]+):(\d+):\s*(.+)")
        start_pattern = re.compile(
            r"Mutation points = \d+, unit test time limit \d+\.\d+s"
        )
        end_pattern = re.compile(r"Jumbling took \d+\.\d+s")
        error_pattern = re.compile(r"Score: \d+%\s*\(?([\w ]+)?")

        # check if there were some errors with Jumble
        errmsg = error_pattern.search(content).group(1)
        if errmsg:
            raise JumbleReportError(errmsg)

        i = start_pattern.search(content).end()
        j = end_pattern.search(content[i:]).start() + i

        # this is the actual text regarding mutations
        text = content[i:j]

        # subtract from text all the fails + get count of them
        killed_text, live_mutants_count = fail_pattern.subn("", text)
        killed_mutants_count = len(re.sub(r"\s+", "", killed_text))

        JumbleMutant.reset_counter()
        self._killed_mutants_count = killed_mutants_count
        self.live_mutants = [
            JumbleMutant.from_tuple(atuple) for atuple in fail_pattern.findall(text)
        ]
        assert self.live_mutants_count == live_mutants_count


class MajorReport(MultipleFilesReport):
    def __init__(
        self,
        mutation_log_fp: Union[str, os.PathLike],
        kill_csv_fp: Union[str, os.PathLike],
    ):
        self.mutation_log_fp = mutation_log_fp
        self.kill_csv_fp = kill_csv_fp
        super(MajorReport, self).__init__(mutation_log_fp, kill_csv_fp)

    def __repr__(self):
        return "Major" + super(MajorReport, self).__repr__()

    def extract(self):
        if len(self.filepaths) != 2:
            raise MajorReportError(
                "Two files must be provided! kill.csv and mutants.log"
            )

        logfile, csvfile = self.mutation_log_fp, self.kill_csv_fp

        columns = ["MutantNo", "Status"]
        kill_df = pd.read_csv(csvfile, header=0, names=columns).set_index(columns[0])

        columns = [
            "MutantNo",
            "Operator",
            "From",
            "To",
            "Signature",
            "LineNumber",
            "Description",
        ]
        mutants_df = pd.read_csv(
            logfile, delimiter=":", header=None, names=columns, on_bad_lines='skip'
        ).set_index(columns[0])

        # fix mismatch in length
        if kill_df.empty or len(kill_df) == 0:
            # empty kill csv -> all mutants are live
            kill_df = pd.DataFrame(["LIVE"] * len(mutants_df), columns=["Status"])
            kill_df.index.name = "MutantNo"

        df = mutants_df.join(kill_df)
        live_mutants = df.loc[df.Status == "LIVE"]
        killed_mutants = df.loc[df.index.difference(live_mutants.index)]
        live_count = len(live_mutants)
        killed_count = len(killed_mutants)
        #assert len(df) == live_count + killed_count

        MajorMutant.reset_counter()
        self.live_mutants = []
        self.killed_mutants = []
        classes = []

        for index, row in df.iterrows():
            mutant = MajorMutant.from_series(row)
            cls = str(mutant.signature).split("@")[0]  # ensure signature is a string
            cls = cls.split("$")[0]  # get the left part of class$subclass
            classes.append(cls)
            if mutant.status == "LIVE":
                self.live_mutants.append(mutant)
            else:
                self.killed_mutants.append(mutant)

        if len(set(classes)) > 1:
            raise MultipleClassUnderMutationError("Multiple classes mutated!")
        else:
            self.class_under_mutation = set(classes).pop()


class PitReport(SingleFileReport):
    def __repr__(self):
        return "Pit" + super(PitReport, self).__repr__()

    def extract(self):
        tree = ET.parse(self.filepath)
        root = tree.getroot()
        elements: List[ET.Element] = list(root)

        self.live_mutants = []
        self.killed_mutants = []
        classes = []

        for element in elements:
            if element.tag != "mutation":
                msg = f"Expecting 'mutation' element, got {element.tag}"
                raise WrongTagInPitReportError(msg)

            mutant = PitMutant.from_xml_element(element)
            classes.append(mutant.mutated_class)
            if mutant.detected:
                self.killed_mutants.append(mutant)
            else:
                self.live_mutants.append(mutant)

        if len(set(classes)) > 1:
            raise MultipleClassUnderMutationError("Multiple classes mutated!")
        else:
            self.class_under_mutation = set(classes).pop()
