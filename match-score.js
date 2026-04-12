(function () {
  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function toArray(value) {
    if (Array.isArray(value)) return value;
    if (value == null || value === '') return [];
    if (typeof value === 'string' || typeof value === 'number') return [value];
    return [];
  }

  function normalizeToken(value) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .replace(/[_-]+/g, ' ')
      .replace(/\s+/g, ' ');
  }

  function normalizeList(values) {
    return toArray(values)
      .map(normalizeToken)
      .filter(Boolean);
  }

  function uniqueList(values) {
    return [...new Set(values)];
  }

  const INTEREST_DOMAIN_MAP = {
    finance: 'finance',
    banking: 'finance',
    budgeting: 'finance',
    budget: 'finance',
    payments: 'finance',
    payment: 'finance',
    fintech: 'finance',
    investing: 'finance',
    insurance: 'finance',
    loans: 'finance',
    shopping: 'consumer',
    beauty: 'consumer',
    fashion: 'consumer',
    retail: 'consumer',
    groceries: 'consumer',
    consumer: 'consumer',
    health: 'health',
    wellness: 'health',
    parenting: 'health',
    family: 'health',
    fitness: 'health',
    medical: 'health',
    gaming: 'tech',
    saas: 'tech',
    software: 'tech',
    apps: 'tech',
    app: 'tech',
    mobile: 'tech',
    ai: 'tech',
    gadgets: 'tech',
    'developer tools': 'tech',
  };

  const DOMAIN_AFFINITY = {
    finance:  { finance: 1, consumer: 0.35, health: 0.05, tech: 0.10 },
    consumer: { consumer: 1, finance: 0.35, health: 0.25, tech: 0.05 },
    health:   { health: 1, consumer: 0.25, finance: 0.05, tech: 0.05 },
    tech:     { tech: 1, finance: 0.10, consumer: 0.05, health: 0.05 },
  };

  function getInterestDomains(interests) {
    return uniqueList(
      interests
        .map((interest) => INTEREST_DOMAIN_MAP[interest])
        .filter(Boolean)
    );
  }

  function getDomainAffinity(studyInterests, contributorInterests) {
    const studyDomains = getInterestDomains(studyInterests);
    const contributorDomains = getInterestDomains(contributorInterests);
    let best = 0;

    for (const studyDomain of studyDomains) {
      for (const contributorDomain of contributorDomains) {
        best = Math.max(best, DOMAIN_AFFINITY[studyDomain]?.[contributorDomain] || 0);
      }
    }

    return best;
  }

  function getContributorInterests(contributor) {
    return uniqueList([
      ...normalizeList(contributor?.interests),
      ...normalizeList(contributor?.interests_lifestyle),
      ...normalizeList(contributor?.interests_tech),
      ...normalizeList(contributor?.interests_finance),
    ]);
  }

  function getContributorFormats(contributor) {
    const availability = contributor?.availability;
    return uniqueList([
      ...normalizeList(contributor?.study_formats),
      ...normalizeList(availability?.study_formats),
      ...normalizeList(availability?.formats),
      ...normalizeList(availability),
    ]);
  }

  function formatAliases(format) {
    const normalized = normalizeToken(format);
    switch (normalized) {
      case 'video call':
      case 'video_call':
      case '1 1':
      case 'one to one':
      case 'one_to_one':
        return ['video call', 'video_call', '1 1', 'one to one', 'one_to_one'];
      case 'focus group':
      case 'focus_group':
      case 'group':
      case 'group session':
        return ['focus group', 'focus_group', 'group', 'group session'];
      case 'in person':
      case 'in_person':
      case 'in person interview':
        return ['in person', 'in_person', 'in person interview'];
      case 'online survey':
      case 'online_survey':
      case 'survey':
        return ['online survey', 'online_survey', 'survey'];
      case 'diary study':
      case 'diary_study':
      case 'journal study':
        return ['diary study', 'diary_study', 'journal study'];
      case 'product testing':
      case 'product_testing':
      case 'product testing at home':
        return ['product testing', 'product_testing', 'product testing at home'];
      default:
        return normalized ? [normalized] : [];
    }
  }

  function getAvailabilityState(contributor, study) {
    const studyFormats = formatAliases(study?.format);
    if (!studyFormats.length) return 'not_required';
    const contributorFormats = getContributorFormats(contributor);
    if (!contributorFormats.length) return 'unknown';
    const normalizedContributorFormats = new Set(
      contributorFormats.flatMap(formatAliases)
    );
    return studyFormats.some((format) => normalizedContributorFormats.has(format))
      ? 'matched'
      : 'unavailable';
  }

  function getFormatLabel(format) {
    const labels = {
      video_call: 'video call',
      focus_group: 'focus group',
      in_person: 'in-person study',
      online_survey: 'online survey',
      diary_study: 'diary study',
      product_testing: 'product test',
    };
    return labels[format] || normalizeToken(format) || 'study format';
  }

  function matchScore(contributor, study) {
    if (!contributor || !study) return { score: 0, reasons: [] };

    const reasons = [];
    const studyInterests = uniqueList(normalizeList(study.target_interests));
    const contributorInterests = getContributorInterests(contributor);
    const interestMatches = studyInterests.filter((tag) => contributorInterests.includes(tag));

    const availabilityState = getAvailabilityState(contributor, study);
    const availabilityMatch = availabilityState === 'matched' || availabilityState === 'not_required';
    if (availabilityState === 'unknown') {
      reasons.push(`Availability not set for ${getFormatLabel(study.format)}`);
    } else if (availabilityState === 'unavailable') {
      reasons.push(`Not available for ${getFormatLabel(study.format)}`);
    } else if (availabilityState === 'matched') {
      reasons.push(`Available for ${getFormatLabel(study.format)}`);
    }

    if (!availabilityMatch) {
      return {
        score: 0,
        reasons: reasons.filter((reason) => typeof reason === 'string' && reason).slice(0, 4),
      };
    }

    let score = 0;
    let qualityMultiplier = 1;

    if (studyInterests.length) {
      const interestRatio = interestMatches.length / studyInterests.length;
      const precision = interestMatches.length / Math.max(contributorInterests.length, 1);

      if (interestMatches.length > 0) {
        score += Math.round((interestRatio * 60) + (precision * 20));
        reasons.push(
          interestMatches.length === 1
            ? 'Matches 1 target interest'
            : `Matches ${interestMatches.length} target interests`
        );
      } else {
        const domainAffinity = getDomainAffinity(studyInterests, contributorInterests);
        score += Math.round(domainAffinity * 15);
        qualityMultiplier = domainAffinity > 0 ? domainAffinity : 0.05;
        reasons.push(
          domainAffinity >= 0.25
            ? 'Adjacent interests'
            : 'No target interest overlap'
        );
      }
    }

    const rating = parseFloat(contributor.rating);
    const minRating = parseFloat(study.min_rating);
    if (!Number.isNaN(rating)) {
      const ratingFloor = Number.isNaN(minRating) ? 3 : clamp(minRating, 0, 5);
      const ratingSpan = Math.max(5 - ratingFloor, 0.1);
      const normalizedRating = clamp((rating - ratingFloor) / ratingSpan, 0, 1);
      score += Math.round(normalizedRating * 15 * qualityMultiplier);

      if (!Number.isNaN(minRating) && rating >= minRating) {
        reasons.push(`Meets ${minRating.toFixed(1)}★ minimum rating`);
      } else if (rating >= 4.5) {
        reasons.push('High contributor rating');
      } else if (rating >= 4.0) {
        reasons.push('Solid contributor rating');
      }
    }

    const completedStudies = Math.max(
      0,
      Number(contributor.completed_studies ?? contributor.total_studies ?? 0) || 0
    );
    const experienceRatio = clamp(completedStudies / 10, 0, 1);
    score += Math.round(experienceRatio * 5 * qualityMultiplier);
    if (completedStudies >= 5) {
      reasons.push('Experienced participant');
    } else if (completedStudies > 0) {
      reasons.push(`Completed ${Math.round(completedStudies)} ${Math.round(completedStudies) === 1 ? 'study' : 'studies'}`);
    }

    return {
      score: clamp(Math.round(score), 0, 100),
      reasons: reasons.filter((reason) => typeof reason === 'string' && reason).slice(0, 4),
    };
  }

  window.matchScore = matchScore;
})();
